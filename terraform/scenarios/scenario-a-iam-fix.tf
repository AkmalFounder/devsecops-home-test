# ==============================================================================
# Mandatory Security Scenario A: Overly Permissive IAM Remediation
# ==============================================================================
# The Insecure Developer Proposal:
# {
#   "Version": "2012-10-17",
#   "Statement": [{ "Effect": "Allow", "Action": "*", "Resource": "*" }]
# }
#
# WHY THIS POLICY IS DANGEROUS:
# 1. Total Account Takeover: Grants full AdministratorAccess to the CI/CD pipeline.
#    Any compromised CI/CD token or malicious pull request can wipe out all AWS
#    resources, delete audit trails (CloudTrail), create rogue admin backdoors,
#    or spin up cryptocurrency miners.
# 2. Privilege Escalation: A pipeline job can attach admin policies to other roles.
# 3. Violation of Least Privilege (PoLP): CI/CD should only deploy specific apps,
#    not modify billing, delete KMS keys, or modify root security settings.
# 4. Long-Lived Static Credential Risk: If AWS_ACCESS_KEY_ID & AWS_SECRET_ACCESS_KEY
#    are used, leakage in CI logs exposes perpetual root-level access.
#
# SAFER ARCHITECTURAL APPROACH:
# 1. OpenID Connect (OIDC) Federated Identity: No hardcoded static credentials.
#    GitLab CI / GitHub Actions exchanges a short-lived JSON Web Token (JWT)
#    for temporary AWS STS credentials valid for only 15-60 minutes.
# 2. Strict Subject Condition: Only jobs running on 'main' branch in the designated
#    repository can assume the deployment role.
# 3. Resource-Level Scoped Permissions: Restricted strictly to ECR push,
#    ECS task definition registration, ECS service update, and scoped iam:PassRole.
# ==============================================================================

# OIDC Provider Trust Policy for CI/CD Runner (e.g., GitHub Actions or GitLab CI)
resource "aws_iam_role" "cicd_deployment_role" {
  name        = "cicd-production-deployer-role"
  description = "Scoped, short-lived deployment role assumed via OIDC"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "OIDCTrustRelationship"
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Restrict strictly to your repository and main/production branch
            "token.actions.githubusercontent.com:sub" = "repo:AkmalFounder/devsecops-home-test:ref:refs/heads/main"
          }
        }
      }
    ]
  })
}

# Least-Privilege Deployment Policy (Resource-level scoping)
resource "aws_iam_policy" "cicd_deployer_policy" {
  name        = "cicd-least-privilege-deployer-policy"
  description = "Minimal permissions required to build, scan, and deploy ECS service"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # 1. Allow ECR Authentication & Image Push
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "arn:aws:ecr:ap-southeast-1:${data.aws_caller_identity.current.account_id}:repository/devsecops-backend"
      },
      # 2. Allow ECS Service Update & Task Registration
      {
        Sid    = "ECSDeploy"
        Effect = "Allow"
        Action = [
          "ecs:RegisterTaskDefinition",
          "ecs:DescribeTaskDefinition",
          "ecs:DescribeServices",
          "ecs:UpdateService"
        ]
        Resource = [
          "arn:aws:ecs:ap-southeast-1:${data.aws_caller_identity.current.account_id}:task-definition/devsecops-backend-*",
          "arn:aws:ecs:ap-southeast-1:${data.aws_caller_identity.current.account_id}:service/devsecops-backend-production-cluster/*"
        ]
      },
      # 3. Controlled PassRole: Can only pass explicitly approved execution roles to ECS
      {
        Sid    = "ScopedPassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/devsecops-backend-production-task-execution-role",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/devsecops-backend-production-task-role"
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_cicd_deployer" {
  role       = aws_iam_role.cicd_deployment_role.name
  policy_arn = aws_iam_policy.cicd_deployer_policy.arn
}
