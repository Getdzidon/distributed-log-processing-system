variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "secondary_region" {
  description = "Secondary AWS region for HA"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  validation {
    condition     = contains(["dev", "production"], var.environment)
    error_message = "Environment must be dev or production"
  }
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "secondary_vpc_cidr" {
  description = "CIDR block for secondary region VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
}

variable "secondary_availability_zones" {
  description = "Secondary region availability zones"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

variable "eks_cluster_version" {
  description = "EKS cluster version"
  type        = string
  default     = "1.28"
}

variable "enable_multi_region" {
  description = "Enable multi-region deployment"
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Domain name for Route53"
  type        = string
  default     = "cmg-logs.example.com"
}
