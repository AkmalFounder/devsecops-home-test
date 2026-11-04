# DevSecOps Incident Response, Troubleshooting & DAST Architecture

This document provides formal technical responses for **Task 5 (Troubleshooting & Incident Response)** and **Task 6 (DAST & OWASP Top 10)**.

---

# Part 1: Task 5 - Troubleshooting & Incident Response Scenarios

---

## Scenario A: Pipeline Security Failure (Critical CVE in Base Image)

### Scenario Context
A CI/CD pipeline fails because Trivy reports a `CRITICAL` vulnerability in the Docker base image. The development team argues that the application logic works perfectly and demands an immediate bypass to deploy directly to production.

### Operational Response Protocol

```mermaid
sequenceDiagram
    autonumber
    participant Dev as Development Team
    participant Sec as DevSecOps Engineer
    participant CISO as CISO / Security Approver
    participant CI as CI/CD Pipeline

    Dev->>Sec: "App is working fine, please bypass Trivy and deploy to prod!"
    Sec->>Sec: Triage CVE (CVSS, EPSS, Reachability & Remote Exploitability)
    alt Fix Available via Minor Bump
        Sec->>Dev: Provide updated base image tag (e.g. node:20-alpine3.20)
        Dev->>CI: Push fix, scan passes, deploy succeeds
    else No Immediate Upstream Fix Available
        Sec->>Dev: Evaluate Compensating Controls (WAF rule, Drop Capabilities)
        Sec->>CISO: Submit Time-Bound Security Exception Request (Max 14 days)
        CISO-->>Sec: Approve Exception with conditions
        Sec->>CI: Add scoped temporary entry in .trivyignore with expiration
        CI-->>Dev: Pipeline unblocked for production release
    end
```

### 1. Risk Assessment
- **Do not bypass blindfolded**: A working application does not equate to a secure application. A vulnerable base image library (e.g., glibc, OpenSSL, or busybox) can allow arbitrary remote code execution (RCE) regardless of the application code quality.
- **Triage Steps**:
  1. Inspect the CVE ID, CVSS score, and EPSS (Exploit Prediction Scoring System) score.
  2. Check if a public Proof-of-Concept (PoC) exploit exists in the wild.
  3. Determine **Reachability**: Is the vulnerable binary or C-library invoked by the Node.js runtime? Does exploitation require root privileges that our non-root container prevents?

### 2. Immediate Remediation Options
- **Option 1 (Fastest Fix)**: Bump the base image tag. Often, using the latest patch version (e.g., updating `node:20.10-alpine` to `node:20-alpine3.20`) resolves the CVE immediately.
- **Option 2 (Image Re-architecture)**: Migrate to a Distroless or Chainguard image that contains zero package managers, shells, or unneeded system utilities.

### 3. Exception & Release Authorization Framework
If the deployment is business-critical and no immediate patch exists:
- An **Emergency Security Exception Request** must be filled out detailing:
  - Compensating controls applied (e.g., AWS WAF virtual patch, egress traffic restrictions).
  - Explicit justification for why the vulnerability is not exploitable in the current deployment topology.
- **Release Authorization**: The bypass **cannot** be authorized by the developers alone. It requires formal sign-off from the **Lead DevSecOps Engineer** and the **CISO/Engineering Director**.
- The bypass is documented inside `.trivyignore` with a hard expiration timestamp (e.g., 7–14 days).

---

## Scenario B: ECS Fargate Application Cannot Retrieve Secrets

### Scenario Context
An ECS Fargate task fails during task startup (`ResourceInitializationError` / `STOPPED`) because it cannot retrieve database secrets from AWS Secrets Manager.

### Step-by-Step Investigation & Troubleshooting Process
To isolate the root cause **without** granting dangerous, broad administrator privileges (`AdministratorAccess` or `secretsmanager:*`):

```mermaid
flowchart TD
    Start["ECS Task Fails: ResourceInitializationError"] --> Step1["1. Inspect ECS Stopped Reason & CloudWatch Logs"]
    Step1 --> Step2{"Is it AccessDenied or Network Timeout?"}
    Step2 -->|AccessDenied on SecretsManager| Step3["2. Check ECS Task Execution Role IAM Policy"]
    Step2 -->|AccessDenied on KMS| Step4["3. Check KMS Key Policy (kms:Decrypt)"]
    Step2 -->|Connection Timed Out| Step5["4. Check VPC Endpoints & Security Groups"]
    
    Step3 --> FixIAM["Grant scoped secretsmanager:GetSecretValue to Secret ARN"]
    Step4 --> FixKMS["Add Task Execution Role ARN to KMS Key Policy Condition"]
    Step5 --> FixNet["Verify com.amazonaws.secretsmanager Interface Endpoint & SG Port 443"]
```

### 1. Inspect Task Stopped Reason via AWS CLI / Console
Run the diagnostic command to inspect the exact failure message:
```bash
aws ecs describe-tasks \
  --cluster devsecops-backend-production-cluster \
  --tasks <task-id> \
  --query 'tasks[0].stoppedReason'
```
*Typical errors*:
- `AccessDeniedException: User: arn:aws:sts::... is not authorized to perform: secretsmanager:GetSecretValue`
- `AccessDeniedException: The ciphertext refers to a customer master key which does not exist or you do not have permission to access`
- `FetchSecretError: Connection timed out`

### 2. Verify Task Execution Role vs. Task Role
- **Crucial Distinction**: The container's application code uses the `task_role`. However, the initialization step where ECS pulls images and decrypts secrets into container memory is executed by the **`task_execution_role`**.
- **Investigation**: Ensure the `execution_role_arn` on the task definition has the inline policy:
  ```json
  {
    "Effect": "Allow",
    "Action": "secretsmanager:GetSecretValue",
    "Resource": "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:devsecops/prod/db-credentials-*"
  }
  ```

### 3. Verify AWS KMS Customer Managed Key (CMK) Permissions
- If the secret is encrypted with a custom KMS key (not the default `aws/secretsmanager` key), the `task_execution_role` must have `kms:Decrypt` permission on that specific key ARN.
- Additionally, inspect the **KMS Key Policy**: Ensure the key policy allows the IAM role or AWS Account root to grant decrypt rights.

### 4. Verify Network Connectivity & VPC Endpoints
- Since ECS Fargate tasks reside in **Private Subnets** without public IPs:
  - Does the subnet route table route `0.0.0.0/0` to a functioning **NAT Gateway**?
  - OR, if running in an isolated VPC without NAT: Are **AWS PrivateLink VPC Endpoints** provisioned for:
    1. `com.amazonaws.ap-southeast-1.secretsmanager`
    2. `com.amazonaws.ap-southeast-1.kms`
  - **Security Group Check**: Ensure the Security Group attached to the VPC Interface Endpoints allows inbound TCP traffic on port 443 from the ECS Tasks Security Group (`sg-ecs`).

---

## Scenario C: Unauthorized AWS API Activity from CI/CD IAM Principal

### Scenario Context
AWS CloudTrail / Amazon GuardDuty triggers a high-severity alert showing anomalous API calls (e.g., `CreateUser`, `CreateAccessKey`, `AuthorizeSecurityGroupIngress 0.0.0.0/0`, or bulk data queries) originating from the IAM principal assigned to the CI/CD deployment pipeline.

### Immediate Containment, Investigation, and Recovery (SANS Incident Handling)

```mermaid
flowchart LR
    subgraph Phase1 [" 1. Immediate Containment "]
        Revoke["Attach Explicit DENY-ALL Policy"]
        DeleteKey["Deactivate & Delete Static Access Keys"]
        Invalidate["Invalidate Active STS Sessions"]
    end

    subgraph Phase2 [" 2. Forensic Investigation "]
        Trail["CloudTrail Event Query"]
        Scope["Determine Blast Radius & Attacker IP"]
        GitCheck["Audit CI/CD Run Logs for Leaked Secrets"]
    end

    subgraph Phase3 [" 3. Eradication & Recovery "]
        Purge["Destroy Attacker Backdoors / Rogue Resources"]
        Rotate["Rotate Downstream Database & API Secrets"]
        OIDC["Migrate Exclusively to OIDC Federation"]
    end

    Phase1 --> Phase2 --> Phase3
```

### Phase 1: Immediate Containment (Stop the Bleeding - < 15 Minutes)
1. **Revoke Active Sessions & Attach Inline Deny-All Policy**:
   Immediately terminate all running sessions under that IAM Role/User without deleting the role itself (preserving audit forensics):
   ```bash
   aws iam put-role-policy \
     --role-name cicd-production-deployer-role \
     --policy-name EmergencyQuarantineDenyAll \
     --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Deny","Action":"*","Resource":"*"}]}'
   ```
2. **Invalidate Active STS Credentials**:
   Attach an AWS RevokeOlderSessions policy revoking any token issued before the current timestamp:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Deny",
       "Action": ["*"],
       "Resource": ["*"],
       "Condition": { "DateLessThan": { "aws:TokenIssueTime": "2026-11-03T12:00:00Z" } }
     }]
   }
   ```
3. **Deactivate Compromised Static Keys**: If static access keys were used, deactivate them immediately:
   ```bash
   aws iam update-access-key --access-key-id AKIAIOSFODNN7EXAMPLE --status Inactive
   ```
4. **Pause CI/CD Pipeline**: Temporarily suspend the GitLab/GitHub Actions pipeline to prevent automated runs while investigating.

### Phase 2: Forensic Investigation & Root Cause Analysis
1. **Query CloudTrail Logs**:
   Use CloudWatch Insights or Athena to reconstruct the attacker's timeline:
   ```sql
   SELECT eventTime, eventName, sourceIPAddress, userAgent, requestParameters
   FROM cloudtrail_logs
   WHERE userIdentity.arn LIKE '%cicd-production-deployer-role%'
     AND eventTime > '2026-11-03T00:00:00Z'
   ORDER BY eventTime ASC;
   ```
2. **Identify Blast Radius**:
   - Check if any new IAM users, access keys, or roles were created (persistence mechanisms).
   - Check if Security Groups were modified to open ports 22, 3389, or 5432 to `0.0.0.0/0`.
   - Check if snapshots, S3 buckets, or RDS databases were made public or exfiltrated.
3. **Investigate Initial Infection Vector**:
   - Were static credentials printed in CI/CD build logs or cached in pipeline artifacts?
   - Did a malicious pull request execute arbitrary bash commands in the CI runner?
   - Was a third-party CI/CD action/plugin compromised (supply chain attack)?

### Phase 3: Eradication, Recovery & Post-Mortem
1. **Eradicate Malicious Assets**: Delete all rogue resources, IAM users, and backdoors identified during CloudTrail forensics.
2. **Rotate All Downstream Secrets**: Assume all secrets accessible to that role were compromised; rotate RDS passwords, API tokens, and JWT secrets.
3. **Hardened Architecture**:
   - Eliminate static AWS Access Keys permanently.
   - Enforce **IAM OpenID Connect (OIDC)** with strict claims validation (`aud` and `sub: repo:owner/repo:ref:refs/heads/main`).
   - Enable Amazon GuardDuty with automated Lambda remediation.
4. **Post-Mortem**: Document timeline, root cause, detection gaps, and preventive milestones in an official blameless post-mortem document.

---

# Part 2: Task 6 - DAST and OWASP Top 10 Integration

---

## 1. DAST Implementation Architecture with OWASP ZAP

Dynamic Application Security Testing (DAST) assesses the running application from the outside, testing for vulnerabilities that only emerge during runtime (e.g., authentication flaws, server misconfigurations, input handling).

```mermaid
flowchart LR
    subgraph Staging_Environment [" Isolated Ephemeral Test Environment "]
        TestApp["Backend API Container<br/>(Mock DB & Test Secrets)"]
    end

    subgraph CI_Runner [" CI/CD Pipeline Job "]
        ZAP["OWASP ZAP Container<br/>(zap-baseline.py / zap-api-scan.py)"]
        Spec["OpenAPI / Swagger Spec<br/>(swagger.json)"]
    end

    Spec --> ZAP
    ZAP -->|Active & Passive Attacks| TestApp
    ZAP -->|Generate Report| Artifacts["DAST Report (zap-report.html / JSON)"]
    Artifacts --> Gate{"High/Critical Findings?"}
    Gate -->|Yes| Fail["Fail Pipeline (Exit 1)"]
    Gate -->|No| Pass["Promote to Production Deployment"]
```

---

## 2. Technical Responses to Core DAST Questions

### 1. How the Application is Made Available in a Safe Test Environment
- **Ephemeral Containerized Environment**: The CI/CD pipeline spins up an isolated, short-lived container network using Docker Compose or a dedicated Kubernetes/ECS staging namespace.
- **Isolated Mock Dependencies**: The test environment connects to mock services or an isolated ephemeral PostgreSQL container pre-populated with synthetic, non-production test data.
- **Zero Real Customer Data**: No production databases or PII (Personally Identifiable Information) are ever attached to the test target.

### 2. Which DAST Checks Are Executed Automatically
- **Passive Scanning**:
  - Validates security headers (Helmet): Missing `Content-Security-Policy`, `Strict-Transport-Security (HSTS)`, `X-Content-Type-Options`, `X-Frame-Options`.
  - Information disclosure: Leaked server banners (e.g., `X-Powered-By: Express`), detailed stack traces, sensitive paths (`/.git`, `/.env`).
  - Cookie security: Missing `HttpOnly`, `Secure`, and `SameSite` flags.
- **Active / API Scanning (via OpenAPI/Swagger)**:
  - **SQL Injection (SQLi)** and NoSQL injection payloads in URL query parameters and JSON bodies.
  - **Cross-Site Scripting (XSS)** reflected and stored in responses.
  - **Authentication / Authorization bypass**: Tampering with tokens, IDOR parameters, and HTTP method tampering (PUT/DELETE on read-only endpoints).
  - Rate limiting & Denial-of-Service checks against large payloads.

### 3. How Authentication is Handled During Testing
- **Automated Token Generation**: The pipeline runner calls a test authentication endpoint (`/api/v1/auth/login`) with ephemeral test credentials to obtain a signed JWT Bearer Token.
- **Header Injection**: OWASP ZAP injects the token into every scanning request using the `-z "-config replacer.full_list(0).description=auth -config replacer.full_list(0).enabled=true -config replacer.full_list(0).matchtype=REQ_HEADER -config replacer.full_list(0).matchstr=Authorization -config replacer.full_list(0).regex=false -config replacer.full_list(0).replacement='Bearer <TOKEN>'"` flag or ZAP Automation Framework (ZAF) configuration.

### 4. Which Findings Should Block a Release
- **Mandatory Release Blockers (Fail Pipeline)**:
  - Any **CRITICAL** or **HIGH** severity finding:
    - Remote Code Execution (RCE)
    - SQL / Command Injection
    - Broken Authentication / Unauthorized Access (BOLA / IDOR)
    - Sensitive Data Exposure (API leaking passwords or private keys)
- **Non-blocking (Tracked in Backlog)**:
  - Medium / Low severity findings (e.g., missing anti-clickjacking headers on purely JSON APIs, verbose error messages in non-production environments).

### 5. Preventing Security Testing from Affecting Production Systems
1. **Network & Target Segregation**:
   - The DAST target URL is strictly hardcoded to the local runner (`http://localhost:8080`) or the dedicated staging environment (`https://staging-api.internal`).
   - Production URLs are strictly blacklisted in CI/CD pipeline variables and protected by AWS WAF rate limits.
2. **Safe Test Accounts**:
   - Automated active scans are performed using designated sandbox test user IDs that have no access to production databases.
3. **Mocking Destructive Operations**:
   - Dangerous endpoints (e.g., `/api/v1/user/delete-all` or payment trigger endpoints) are stubbed or excluded in the ZAP configuration file.

---

## 3. Relevant OWASP Top 10 Risks: Detection & Mitigation

### 1. A01: Broken Access Control (BOLA / IDOR)
- **Threat**: An authenticated user modifies resource identifiers (such as changing `userId=101` to `userId=102` in an API call) to view or tamper with another tenant's private data.
- **Detection**: DAST (OWASP ZAP) parameter fuzzing using multiple authentication tokens with different privilege levels, combined with SonarQube SAST security rules detecting missing authorization checks before data retrieval.
- **Mitigation**: Implement strict server-side claims validation to ensure the requesting user session owns the requested record before executing queries.

### 2. A03: Injection (SQL / Command Injection)
- **Threat**: An attacker supplies malicious SQL fragments through query parameters or request bodies to bypass authentication or extract backend database tables.
- **Detection**: SonarQube SAST rules flagging string concatenation in database statements, alongside OWASP ZAP active injection attack plugins testing API endpoints.
- **Mitigation**: Use parameterized SQL queries, ORM frameworks, and strict input validation schemas (such as Joi or Zod middleware).

### 3. A05: Security Misconfiguration
- **Threat**: Insecure default settings, unencrypted data stores, missing HTTP security headers, or open security groups exposing ports to the internet (`0.0.0.0/0`).
- **Detection**: Automated Checkov IaC scans on Terraform configurations, and OWASP ZAP passive scans verifying HTTP security headers (HSTS, CSP, and X-Content-Type-Options).
- **Mitigation**: Apply automated CIS AWS benchmarks in Terraform, enforce strict chained security groups, and enable Helmet middleware in the Node.js application.
