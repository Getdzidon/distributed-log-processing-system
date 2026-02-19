# Secondary Region Module

Deploys infrastructure in a secondary AWS region for multi-region high availability.

## Resources Created

- VPC with public/private subnets
- EKS cluster
- NAT gateways
- Internet gateway

## Usage

This module is currently commented out in `main.tf`. To enable:

1. Uncomment the `secondary_region` module block in `main.tf`
2. Set `enable_multi_region = true` in your tfvars file
3. Ensure AWS credentials have access to the secondary region
4. Run `terraform apply`

## Requirements

- Additional EKS cluster costs (~$73/month per cluster)
- Cross-region data transfer costs
- Increased operational complexity

## Outputs

- `vpc_id` - Secondary region VPC ID
- `cluster_endpoint` - Secondary EKS cluster endpoint
- `cluster_name` - Secondary EKS cluster name
