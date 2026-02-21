# GitHub Secrets Configuration

## Required Secrets

Configure these secrets in GitHub: **Settings → Secrets and variables → Actions**

### Repository Secrets

| Secret Name | Description | How to Get | Used By |
|------------|-------------|------------|---------||
| `AWS_ROLE_ARN` | IAM role ARN for GitHub Actions OIDC | Bootstrap Terraform output | All workflows |
| `ECR_REPOSITORY` | ECR repository URL | Terraform output or AWS console | dev.yml, production.yml |
| `DEV_QUEUE_URL` | Dev SQS queue URL | Terraform output after dev deployment | dev.yml |
| `DEV_S3_BUCKET` | Dev S3 bucket name | Terraform output after dev deployment | dev.yml |
| `DEV_DYNAMODB_TABLE` | Dev DynamoDB table name | Terraform output after dev deployment | dev.yml |
| `DEV_SERVICE_ACCOUNT_ROLE_ARN` | Dev IRSA role ARN | Terraform output after dev deployment | dev.yml |
| `PROD_QUEUE_URL` | Production SQS queue URL | Terraform output after production deployment | production.yml |
| `PROD_S3_BUCKET` | Production S3 bucket name | Terraform output after production deployment | production.yml |
| `PROD_DYNAMODB_TABLE` | Production DynamoDB table name | Terraform output after production deployment | production.yml |
| `PROD_SERVICE_ACCOUNT_ROLE_ARN` | Production IRSA role ARN | Terraform output after production deployment | production.yml |

## How to Get Secret Values

### 1. AWS_ROLE_ARN (Bootstrap)

Deploy bootstrap infrastructure first:

```bash
cd infrastructure/bootstrap
terraform init
terraform apply

# Get the role ARN
terraform output github_actions_role_arn
# Output: arn:aws:iam::123456789012:role/cmg-log-processor-github-actions
```

### 2. ECR_REPOSITORY

Get ECR repository URL:

```bash
# Option 1: From Terraform (if ECR module exists)
cd infrastructure/terraform
terraform output ecr_repository_url

# Option 2: From AWS CLI
aws ecr describe-repositories --repository-names log-processor --query 'repositories[0].repositoryUri' --output text
# Output: 123456789012.dkr.ecr.eu-central-1.amazonaws.com/log-processor
```

### 3. Dev Environment Secrets

After deploying dev infrastructure:

```bash
cd infrastructure/terraform
terraform workspace select dev

# Get all dev values
terraform output sqs_queue_url
terraform output s3_bucket_name
terraform output dynamodb_table_name
terraform output service_account_role_arn
```

**Example outputs:**
```
DEV_QUEUE_URL: https://sqs.eu-central-1.amazonaws.com/123456789012/cmg-log-processor-dev-queue
DEV_S3_BUCKET: cmg-log-processor-dev-raw-logs
DEV_DYNAMODB_TABLE: cmg-log-processor-dev-metrics
DEV_SERVICE_ACCOUNT_ROLE_ARN: arn:aws:iam::123456789012:role/cmg-log-processor-dev-log-processor
```

### 3. Production Environment Secrets

After deploying production infrastructure:

```bash
cd infrastructure/terraform
terraform workspace select production

# Get all production values
terraform output sqs_queue_url
terraform output s3_bucket_name
terraform output dynamodb_table_name
terraform output service_account_role_arn
```

**Example outputs:**
```
PROD_QUEUE_URL: https://sqs.eu-central-1.amazonaws.com/123456789012/cmg-log-processor-production-queue
PROD_S3_BUCKET: cmg-log-processor-production-raw-logs
PROD_DYNAMODB_TABLE: cmg-log-processor-production-metrics
PROD_SERVICE_ACCOUNT_ROLE_ARN: arn:aws:iam::123456789012:role/cmg-log-processor-production-log-processor
```

## Adding Secrets to GitHub

1. Go to your repository on GitHub
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add each secret from the table above
5. Click **Add secret**

**Quick script to get all values:**

```bash
#!/bin/bash
# Get all secret values for GitHub

echo "=== Bootstrap ==="
cd infrastructure/bootstrap
echo "AWS_ROLE_ARN=$(terraform output -raw github_actions_role_arn)"

echo ""
echo "=== ECR Repository ==="
echo "ECR_REPOSITORY=$(aws ecr describe-repositories --repository-names log-processor --query 'repositories[0].repositoryUri' --output text)"

echo ""
echo "=== Dev Environment ==="
cd ../terraform
terraform workspace select dev
echo "DEV_QUEUE_URL=$(terraform output -raw sqs_queue_url)"
echo "DEV_S3_BUCKET=$(terraform output -raw s3_bucket_name)"
echo "DEV_DYNAMODB_TABLE=$(terraform output -raw dynamodb_table_name)"
echo "DEV_SERVICE_ACCOUNT_ROLE_ARN=$(terraform output -raw service_account_role_arn)"

echo ""
echo "=== Production Environment ==="
terraform workspace select production
echo "PROD_QUEUE_URL=$(terraform output -raw sqs_queue_url)"
echo "PROD_S3_BUCKET=$(terraform output -raw s3_bucket_name)"
echo "PROD_DYNAMODB_TABLE=$(terraform output -raw dynamodb_table_name)"
echo "PROD_SERVICE_ACCOUNT_ROLE_ARN=$(terraform output -raw service_account_role_arn)"
```

## Secrets Usage by Workflow

### terraform.yml
```yaml
role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
```
**Purpose**: Deploy infrastructure (VPC, EKS, S3, DynamoDB, SQS)

### dev.yml
```yaml
role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
--set env[3].value=${{ secrets.DEV_QUEUE_URL }}
--set env[4].value=${{ secrets.DEV_S3_BUCKET }}
--set env[5].value=${{ secrets.DEV_DYNAMODB_TABLE }}
--set serviceAccount.annotations="eks.amazonaws.com/role-arn"=${{ secrets.DEV_SERVICE_ACCOUNT_ROLE_ARN }}
```
**Purpose**: Deploy application to dev EKS cluster with environment-specific values

### production.yml
```yaml
role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
--set env[3].value=${{ secrets.PROD_QUEUE_URL }}
--set env[4].value=${{ secrets.PROD_S3_BUCKET }}
--set env[5].value=${{ secrets.PROD_DYNAMODB_TABLE }}
--set serviceAccount.annotations="eks.amazonaws.com/role-arn"=${{ secrets.PROD_SERVICE_ACCOUNT_ROLE_ARN }}
```
**Purpose**: Deploy application to production EKS clusters with environment-specific values

### reusable-build.yml
```yaml
role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
```
**Purpose**: Push Docker images to ECR

### pr-checks.yml
**No secrets required** - Only runs tests and security scans

## Deployment Order

1. **Deploy Bootstrap** → Get `AWS_ROLE_ARN` → Add to GitHub Secrets
2. **Deploy Dev Infrastructure** → Get dev secrets → Add to GitHub Secrets
3. **Deploy Dev Application** (now works with secrets)
4. **Deploy Production Infrastructure** → Get prod secrets → Add to GitHub Secrets
5. **Deploy Production Application** (now works with secrets)

## Verification

Test that secrets are configured correctly:

```bash
# Trigger a workflow manually
gh workflow run terraform.yml -f environment=dev -f action=plan

# Check the run
gh run list --workflow=terraform.yml
```

Look for successful AWS authentication in logs:
```
Assuming role: arn:aws:iam::123456789012:role/cmg-log-processor-github-actions
Successfully assumed role
```

## Security Best Practices

✅ **Do:**
- Use OIDC (no long-lived credentials)
- Rotate secrets if infrastructure changes
- Use environment protection rules for production
- Enable branch protection

❌ **Don't:**
- Store `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY`
- Commit secrets to code
- Share secrets across repositories
- Hardcode values in Helm charts

## Troubleshooting

**Error: "Secret AWS_ROLE_ARN not found"**
- Verify secret name is exactly `AWS_ROLE_ARN` (case-sensitive)
- Check it's added as repository secret, not environment secret

**Error: "Secret DEV_QUEUE_URL not found"**
- Deploy dev infrastructure first
- Run terraform output to get values
- Add all dev secrets to GitHub

**Error: "Not authorized to perform sts:AssumeRoleWithWebIdentity"**
- Verify OIDC provider exists in AWS IAM
- Check trust policy allows your GitHub repo
- Ensure `github_org` and `github_repo` match in bootstrap terraform

**Error: "Access denied" when deploying**
- Verify role has necessary permissions
- Check `attach_admin_policy = true` in bootstrap terraform.tfvars
- Or uncomment permissions in `deploy-policy.json`
