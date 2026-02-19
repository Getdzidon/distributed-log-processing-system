variable "domain_name" {
  description = "Domain name for Route53 hosted zone"
  type        = string
}

variable "primary_endpoint" {
  description = "Primary region endpoint URL"
  type        = string
}

variable "secondary_endpoint" {
  description = "Secondary region endpoint URL"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name"
  type        = string
}
