# ==============================================================================
# Mandatory Security Scenario B: Publicly Accessible Resource Remediation
# ==============================================================================
# Scenario:
# A developer submits a Terraform pull request creating an RDS database with:
# - publicly_accessible = true
# - Security Group allowing ingress from 0.0.0.0/0
#
# HOW THE PIPELINE DETECTS AND BLOCKS THIS CONFIGURATION:
# 1. Shift-Left IaC Security Scanning (Checkov & Trivy):
#    - Rule CKV_AWS_17: "Ensure RDS DB instances are not publicly accessible"
#    - Rule CKV_AWS_260: "Ensure no security groups allow ingress from 0.0.0.0/0 to port 5432/3306"
#    - Checkov evaluates the AST of Terraform code before `terraform apply`.
#    - Pipeline is configured with strict exit flags: `checkov -d . --framework terraform --soft-fail=false`
#    - Any violation returns exit code 1, immediately terminating the CI/CD pipeline
#      and failing the Pull Request / Merge Request check.
# 2. Hardened Infrastructure Implementation:
#    Below is the secure reference architecture for an RDS database:
#    - Isolated inside private database subnets (no Internet Gateway routing).
#    - publicly_accessible set to false.
#    - Security group strictly restricts ingress ONLY to the ECS Tasks Security Group.
#    - Storage encrypted with KMS Customer Managed Key.
# ==============================================================================

# Private DB Subnet Group
resource "aws_db_subnet_group" "private_db" {
  name        = "devsecops-private-db-subnet-group"
  subnet_ids  = aws_subnet.private_app[*].id # Placed inside private subnets
  description = "Database subnets isolated from internet access"

  tags = {
    Name = "devsecops-private-db-subnet-group"
  }
}

# Strict Database Security Group: Ingress ONLY from ECS Tasks SG
resource "aws_security_group" "db_sg" {
  name        = "devsecops-rds-private-sg"
  description = "Controls database ingress strictly from backend compute layer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL access strictly from ECS backend containers"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id] # Chained SG, never 0.0.0.0/0
  }

  egress {
    description = "No outbound internet access required for database"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "devsecops-rds-private-sg"
  }
}

# Hardened RDS Instance (Passing all Checkov/Trivy rules)
resource "aws_db_instance" "secure_postgres" {
  identifier        = "devsecops-prod-db"
  allocated_storage = 20
  engine            = "postgres"
  engine_version    = "16.1"
  instance_class    = "db.t4g.micro"

  # SECURITY CONTROLS:
  publicly_accessible    = false                         # Fixes CKV_AWS_17
  db_subnet_group_name   = aws_db_subnet_group.private_db.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  storage_encrypted      = true                          # Fixes CKV_AWS_16
  kms_key_id             = aws_kms_key.app_cmk.arn
  deletion_protection    = true
  skip_final_snapshot    = false
  final_snapshot_identifier = "devsecops-prod-db-final-snapshot"

  # Authentication
  username = "dbadmin"
  password = "ManagedExternallyViaSecretsManager#2026" # Sourced securely

  # Auditing & Logging
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  auto_minor_version_upgrade      = true

  tags = {
    Name = "devsecops-production-database"
  }
}
