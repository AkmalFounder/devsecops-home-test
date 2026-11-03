# Mandatory Security Scenario C: Secret Exposure in Terraform & State Remediation

## 1. Problem Statement
An application database password was defined as a plain variable in `terraform.tfvars` or declared as `variable "db_password" { default = "SuperSecret123" }`. As a result:
- The secret is recorded in plain text inside the `terraform.tfstate` file (and state history).
- If `terraform.tfvars` was committed to version control, the secret is permanently stored in the Git commit history.
- Anyone with read access to the state bucket (or Git repository) can decrypt and access the production database.

---

## 2. Immediate Containment & Incident Response (Triage & Rotation)
Do **NOT** simply delete the variable from Git or delete the state file without credential rotation. The credential must be treated as **fully compromised**.

1. **Immediate Credential Invalidation & Rotation**:
   - Log into AWS Secrets Manager or the database directly and generate a new high-entropy password.
   - Update the database credentials and reload backend connection pools.
   - Verify that the old compromised password no longer authenticates.

2. **Revoke Exposed Git Commits**:
   - If the password was committed to Git:
     - Run `git-filter-repo` or BFG Repo-Cleaner to completely rewrite git history and remove the file from all branches and tags.
     - Force-push the sanitized tree: `git push origin --force --all` and notify all team members to re-clone the repository.

3. **Sanitize Terraform State (`terraform.tfstate`)**:
   - If using AWS S3 as the remote backend:
     - Enable S3 Object Versioning lifecycle expiration or permanently delete the older S3 object versions that contained the plain text password.
     - Enforce S3 Bucket Server-Side Encryption (`aws:kms`) and restrict bucket read permissions strictly to the CI/CD deployer role.

---

## 3. Preventive Architecture: Eliminating Secrets from Terraform State

Terraform stores all resource attributes in state by design. To prevent secrets from being exposed:

### Approach 1: Decouple Secret Lifecycle via AWS Secrets Manager (Recommended)
Instead of passing passwords into Terraform variables:
1. Have Terraform provision the `aws_secretsmanager_secret` metadata and KMS key, but **not** the secret value.
2. Let the application or a post-provisioning Lambda/CLI inject the secret value directly into AWS Secrets Manager.
3. In ECS Task Definitions, reference the secret by ARN (`valueFrom: arn:aws:secretsmanager:...:password::`). Terraform only stores the ARN string in state, **never** the secret plaintext!

```hcl
# main.tf
resource "aws_secretsmanager_secret" "db_secret" {
  name        = "production/app/db-credentials"
  kms_key_id  = aws_kms_key.app_cmk.arn
}

# The password is generated and stored externally in Secrets Manager.
# ECS Task Definition references the secret ARN directly:
resource "aws_ecs_task_definition" "app" {
  ...
  container_definitions = jsonencode([
    {
      name    = "backend"
      image   = var.container_image
      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.db_secret.arn}:password::"
        }
      ]
    }
  ])
}
```

### Approach 2: Sensitive Variable Tagging & Git Pre-Commit Hooks
- In Terraform variables, always specify `sensitive = true` to prevent printing in CLI stdout and CI/CD logs:
  ```hcl
  variable "db_password" {
    type      = string
    sensitive = true
  }
  ```
- Install `gitleaks` pre-commit hooks on developer workstations to prevent any staged commit containing AWS keys or password strings.

### Approach 3: Hardened Remote Backend Security
- Encrypt S3 state bucket using KMS Customer Managed Key.
- Apply strict S3 Bucket Policy:
  - Deny all unencrypted uploads (`s3:x-amz-server-side-encryption`).
  - Deny non-TLS transport (`aws:SecureTransport: false`).
  - Restrict `s3:GetObject` strictly to the automated CI/CD pipeline role.
