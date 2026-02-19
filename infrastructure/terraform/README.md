# Terraform Infrastructure

## Two-Environment Setup

This Terraform configuration manages **two separate environments**:

### Environments

| Environment | Workspace | Config File | AWS Region | Purpose |
|-------------|-----------|-------------|------------|---------|
| **Dev** | `dev` | `environments/dev.tfvars` | eu-central-1 | Development and testing |
| **Production** | `production` | `environments/production.tfvars` | eu-central-1 (+ eu-west-1) | Production workloads |

### How It Works

**1. Terraform Workspaces**
- Each environment uses a separate workspace
- State files are isolated: `env:/dev/...` and `env:/production/...`
- Prevents accidental changes across environments

**2. Environment-Specific Variables**
- `dev.tfvars` - Smaller resources, single region
- `production.tfvars` - Larger resources, multi-region HA

**3. Resource Naming**
- Dev: `cmg-log-processor-dev-*`
- Production: `cmg-log-processor-production-*`

## Deployment

### Prerequisites

**IMPORTANT: Deploy bootstrap infrastructure first!**

See [../bootstrap/README.md](../bootstrap/README.md) for one-time setup of:
- S3 backend for Terraform state
- DynamoDB table for state locking  
- GitHub OIDC for CI/CD authentication

### Deploy to Dev

```bash
cd infrastructure/terraform

# Initialize and create workspace
terraform init
terraform workspace new dev
terraform workspace select dev

# Deploy
terraform apply -var-file=environments/dev.tfvars
```

### Deploy to Production

```bash
# Switch to production workspace
terraform workspace new production
terraform workspace select production

# Deploy
terraform apply -var-file=environments/production.tfvars
```

### Check Current Environment

```bash
terraform workspace show
```

### List All Workspaces

```bash
terraform workspace list
```

## State Management

State files are stored in S3 with workspace prefixes:
- Dev: `s3://cmg-terraform-state/env:/dev/log-processor/terraform.tfstate`
- Production: `s3://cmg-terraform-state/env:/production/log-processor/terraform.tfstate`

State locking uses DynamoDB table: `terraform-lock`

## Key Differences Between Environments

| Resource | Dev | Production |
|----------|-----|------------|
| EKS Nodes | 2-3 nodes | 3-10 nodes |
| Instance Type | t3.medium | t3.medium |
| Multi-Region | Disabled | Enabled (eu-central-1 + eu-west-1) |
| S3 Replication | No | Yes |
| DynamoDB Global Tables | No | Yes |

## GitHub Actions OIDC

The `github_oidc` module creates **environment-specific** IAM roles:
- Dev: `cmg-log-processor-github-actions-dev`
- Production: `cmg-log-processor-github-actions-production`

Update `github_org` and `github_repo` in `main.tf` before deploying.

## Modules

All modules use descriptive filenames instead of `main.tf`:
- `modules/vpc/vpc.tf`
- `modules/eks/eks.tf`
- `modules/sqs/sqs.tf`
- `modules/s3/s3.tf`
- `modules/dynamodb/dynamodb.tf`
- `modules/irsa/irsa.tf`
- `modules/github-oidc/github-oidc.tf`
