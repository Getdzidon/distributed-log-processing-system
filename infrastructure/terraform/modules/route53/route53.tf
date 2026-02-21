# Route53 DNS failover configuration for multi-region HA
# Provides automatic failover between primary and secondary regions

# Create hosted zone (assumes domain already exists)
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# Health check for primary endpoint
resource "aws_route53_health_check" "primary" {
  type              = "HTTPS"
  resource_path     = "/healthz"
  fqdn              = replace(var.primary_endpoint, "https://", "")
  port              = 443
  request_interval  = 30
  failure_threshold = 3

  tags = {
    Name        = "${var.environment}-primary-health-check"
    Environment = var.environment
  }
}

# Health check for secondary endpoint
resource "aws_route53_health_check" "secondary" {
  count = var.secondary_endpoint != "" ? 1 : 0

  type              = "HTTPS"
  resource_path     = "/healthz"
  fqdn              = replace(var.secondary_endpoint, "https://", "")
  port              = 443
  request_interval  = 30
  failure_threshold = 3

  tags = {
    Name        = "${var.environment}-secondary-health-check"
    Environment = var.environment
  }
}

# Primary region DNS record (failover primary)
resource "aws_route53_record" "primary" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "CNAME"
  ttl     = 60

  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary.id
  records         = [replace(var.primary_endpoint, "https://", "")]
}

# Secondary region DNS record (failover secondary)
resource "aws_route53_record" "secondary" {
  count = var.secondary_endpoint != "" ? 1 : 0

  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "CNAME"
  ttl     = 60

  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier  = "secondary"
  health_check_id = aws_route53_health_check.secondary[0].id
  records         = [replace(var.secondary_endpoint, "https://", "")]
}

# CloudWatch alarm for primary health check
resource "aws_cloudwatch_metric_alarm" "primary_unhealthy" {
  alarm_name          = "${var.environment}-primary-region-unhealthy"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "Primary region health check failed"
  treat_missing_data  = "breaching"

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary.id
  }
}


