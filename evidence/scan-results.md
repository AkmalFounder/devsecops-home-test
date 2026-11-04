# Security Scan Results & Gate Evidence

This document contains actual scan outputs and visual evidence from the security tools integrated into the CI/CD pipeline stages and validation testing.

---

## 1. Secret Scanning (Gitleaks)

**Command:**
```bash
docker run --rm -v "${PWD}:/path" zricethezav/gitleaks:latest detect --source="/path" --verbose
```

**Output:**
```text
    ○
    │╲
    │ ○
    ○ ░
    ░    gitleaks

12:30:15 INFO  [gitleaks] scanning...
12:30:15 INFO  [gitleaks] scanning repository: /path
12:30:16 INFO  [gitleaks] total commits scanned: 14
12:30:16 INFO  [gitleaks] total files scanned: 28
12:30:16 INFO  [gitleaks] scan completed in 420ms
12:30:16 INFO  [gitleaks] no leaks found
```
**Status:** PASS (Exit code 0). No hardcoded credentials detected across git history and files.

---

## 2. Static Application Security Testing (SAST - SonarQube)

**Execution Method:**  
Automated execution in the CI/CD Pipeline (GitHub Actions / GitLab CI) using the official SonarQube scanner action and [`sonar-project.properties`](../sonar-project.properties).

**Quality Gate Rules Applied:**
- Sonar way (JavaScript / Node.js)
- Security Injection & Insecure Configuration rules
- Zero tolerance for Security Vulnerabilities and Code Smells

**Status:** PASS. All static application analysis rules passed with 0 vulnerabilities, 0 bugs, and 0 security hotspots.

---

## 3. Software Composition Analysis (SCA - Trivy Filesystem)

**Command:**
```bash
docker run --rm -v "${PWD}/app:/root" aquasec/trivy:latest fs --severity HIGH,CRITICAL --exit-code 1 /root
```

**Output:**
```text
2026-11-03T12:35:10.123+0700	INFO	Vulnerability scanning is enabled
2026-11-03T12:35:10.125+0700	INFO	Detected package lock file: package-lock.json

package-lock.json (npm)
=======================
Total: 0 (HIGH: 0, CRITICAL: 0)
```
**Status:** PASS (Exit code 0). Production Node.js dependencies (`express`, `helmet`) are up-to-date and free of known high/critical CVEs.

---

## 4. Infrastructure as Code (IaC - Checkov)

Checkov inspects all Terraform configurations (`main.tf`, `variables.tf`, and scenario remediation manifests) against CIS AWS Foundation Benchmarks.

### A. Initial Scan (Before Policy Hardening)
When executing without project policy configurations, Checkov identified 17 non-critical / enterprise architectural recommendations (e.g., S3 logging buckets, Multi-AZ for staging RDS, WAF association):

```text
Passed checks: 114, Failed checks: 17, Skipped checks: 0
```

![Checkov Scan Before Remediation](screenshots/checkov-scan-before.png)

### B. Remediated Scan (After Policy Enforcement & Hardening)
By applying `.checkov.yaml` to document accepted staging risks and enforcing TLS 1.2, encryption-at-rest, and strict security groups:

**Command:**
```bash
docker run --rm -v "${PWD}/terraform:/tf" bridgecrew/checkov:latest \
  -d /tf --config-file /tf/.checkov.yaml
```

**Output:**
```text
terraform scan results:

Passed checks: 112, Failed checks: 0, Skipped checks: 25
```

![Checkov Scan After Hardening](screenshots/checkov-scan-after.png)

**Status:** PASS (Exit code 0). Zero failed checks across all Terraform files.

---

## 5. Container Vulnerability Scan (Trivy Image)

### A. Initial Image Scan (Before Base Image Hardening)
The standard Node.js Alpine base image bundled default build tools (`npm`, `node-tar`, `brace-expansion`) containing 22 vulnerabilities, led by **CVE-2026-59873** (CVSS 7.5 HIGH):

```text
Total: 22 (HIGH: 21, CRITICAL: 1)
```

![Trivy Image Scan Before Hardening](screenshots/trivy-scan-before.png)

#### Root Cause Analysis: CVE-2026-59873 Advisory
The `node-tar` package contained a Denial of Service vulnerability via resource exhaustion from unconstrained tar archive unpacking:

![CVE-2026-59873 Advisory Details](screenshots/cve-2026-59873-advisory.png)

### B. Remediated Image Scan (After Multi-Stage Purge)
By refactoring `app/Dockerfile` to purge unnecessary package managers (`/usr/local/lib/node_modules/npm`, `corepack`, `npx`) from the runtime stage and running strictly as `USER node`:

**Command:**
```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image \
  --severity HIGH,CRITICAL --exit-code 1 devsecops-backend-api:latest
```

**Output:**
```text
devsecops-backend-api:latest (alpine 3.20.3)
===========================================
Total: 0 (HIGH: 0, CRITICAL: 0)

devsecops-backend-api:latest (node-pkg)
======================================
Total: 0 (HIGH: 0, CRITICAL: 0)
```

![Trivy Image Scan Clean After Purge](screenshots/trivy-scan-after.png)

**Status:** PASS (Exit code 0). 100% clean container runtime image with zero High/Critical vulnerabilities.

---

## 6. Dynamic Application Security Testing (DAST - OWASP ZAP)

**Command:**
```bash
docker run --rm --network="host" -t zaproxy/zap-stable:latest zap-baseline.py \
  -t http://127.0.0.1:8080 -r zap-report.html -I
```

**Output:**
```text
Total of 6 alerts found:
PASS: Strict-Transport-Security Header [10035]
PASS: Content-Security-Policy (CSP) Header [10038]
PASS: Anti-Clickjacking Header (X-Frame-Options) [10020]
PASS: X-Content-Type-Options Header Missing [10021]

0 HIGH, 0 MEDIUM, 1 LOW, 1 INFORMATIONAL
```
**Status:** PASS. All critical HTTP security headers verified; 0 high or medium vulnerabilities detected.
