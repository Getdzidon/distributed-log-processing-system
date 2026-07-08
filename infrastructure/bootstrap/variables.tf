variable "aws_region" {
  description = "AWS region for bootstrap resources"
  type        = string
  default     = "eu-central-1"
}

variable "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  type        = string
  default     = "dlps-terraform-state"
}

variable "lock_table_name" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "terraform-lock"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "dlps-log-processor"
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "distributed-log-processing-system"
}

variable "attach_admin_policy" {
  description = "Attach AdministratorAccess policy (use with caution)"
  type        = bool
  default     = true
}
