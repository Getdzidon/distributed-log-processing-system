output "role_arn" {
  description = "IAM role ARN for service account"
  value       = aws_iam_role.service_account.arn
}
