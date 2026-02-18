variable "cluster_name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "namespace" {
  type = string
}

variable "service_account_name" {
  type = string
}

variable "sqs_queue_arn" {
  type = string
}

variable "s3_bucket_arn" {
  type = string
}

variable "dynamodb_table_arn" {
  type = string
}
