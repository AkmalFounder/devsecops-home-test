# ==============================================================================
# Terraform Outputs
# ==============================================================================

output "vpc_id" {
  description = "The ID of the provisioned VPC"
  value       = aws_vpc.main.id
}

output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "ecs_cluster_name" {
  description = "Name of the ECS Cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS Fargate Service"
  value       = aws_ecs_service.app.name
}

output "task_execution_role_arn" {
  description = "ARN of the ECS Task Execution Role"
  value       = aws_iam_role.ecs_task_execution_role.arn
}

output "task_role_arn" {
  description = "ARN of the ECS Task Application Runtime Role"
  value       = aws_iam_role.ecs_task_role.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS Customer Managed Key"
  value       = aws_kms_key.app_cmk.arn
}

output "secrets_manager_secret_arn" {
  description = "ARN of the DB Secrets Manager Secret"
  value       = aws_secretsmanager_secret.app_db_secret.arn
}
