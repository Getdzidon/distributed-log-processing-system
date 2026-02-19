# Route53 DNS Failover Module

Configures Route53 health checks and DNS failover for multi-region high availability.

## Resources Created

- Route53 health checks (primary and secondary)
- DNS records with failover routing policy
- CloudWatch alarms for health check monitoring

## Usage

This module is currently commented out in `main.tf`. To enable:

1. **Create Route53 hosted zone** for your domain:
   ```bash
   aws route53 create-hosted-zone --name log-processor.cmg.io --caller-reference $(date +%s)
   ```

2. **Update domain nameservers** with your registrar

3. **Uncomment the route53 module** block in `main.tf`

4. **Ensure secondary_region module is enabled** (required for secondary endpoint)

5. Run `terraform apply`

## Requirements

- Route53 hosted zone must exist before applying
- Domain must be registered and nameservers configured
- Secondary region infrastructure must be deployed
- EKS clusters must expose health check endpoints

## Health Check Configuration

- **Endpoint**: `/healthz` on port 443
- **Interval**: 30 seconds
- **Failure threshold**: 3 consecutive failures
- **Failover**: Automatic to secondary region on primary failure

## Outputs

- `hosted_zone_id` - Route53 hosted zone ID
- `primary_health_check_id` - Primary health check ID
- `domain_name` - Configured domain name
