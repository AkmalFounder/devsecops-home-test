# ==============================================================================
# Terraform Variables Definition
# ==============================================================================

variable "aws_region" {
  description = "AWS deployment region"
  type        = string
  default     = "ap-southeast-1"
}

variable "environment" {
  description = "Environment tier (development, staging, production)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "project_name" {
  description = "Name of the project used in resource naming and tags"
  type        = string
  default     = "devsecops-backend"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (ALB & NAT Gateways)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for private application subnets (ECS Tasks)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "private_data_subnet_cidrs" {
  description = "CIDR blocks for private database/cache subnets"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "container_image" {
  description = "URI of the container image in ECR"
  type        = string
  default     = "123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/devsecops-backend:1.0.0"
}

variable "container_port" {
  description = "Port exposed by the backend container"
  type        = number
  default     = 8080
}

variable "tags" {
  description = "Common baseline tags applied to all infrastructure resources"
  type        = map(string)
  default = {
    Project     = "DevSecOps-API"
    ManagedBy   = "Terraform"
    Compliance  = "CIS-Benchmark"
    DataClass   = "Confidential"
  }
}
