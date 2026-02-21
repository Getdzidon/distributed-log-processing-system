output "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  value       = data.aws_route53_zone.main.zone_id
}

output "primary_health_check_id" {
  description = "Primary region health check ID"
  value       = aws_route53_health_check.primary.id
}

output "domain_name" {
  description = "Configured domain name"
  value       = var.domain_name
}