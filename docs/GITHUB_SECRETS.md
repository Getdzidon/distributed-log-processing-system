# GitHub Secrets Configuration

## Required Secrets

Configure these secrets in GitHub: **Settings → Secrets and variables → Actions**

### Repository Secrets

| Secret Name | Description | Example Value | Used By |
|------------|-------------|---------------|---------|
| `AWS_ROLE_ARN` | IAM role ARN for GitHub Actions OIDC | `arn:aws:iam::123456789012:role/cmg-log-processor-github-actions-production` | All workflows |

## How to Get AWS_ROLE_ARN

### Deploy Bootstrap Infrastructure (Recommended)

```bash
cd infrastructure/bootstrap

# Update variables.tf with your GitHub username
terraform init
terraform apply

# Get the role ARN
terraform output github_actions_role_arn
```

See [../bootstrap/README.md](../bootstrap/README.md) for detailed instructions.

## Adding Secrets to GitHub

1. Go to your repository on GitHub
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add each secret:
   - **Name**: `AWS_ROLE_ARN`
   - **Value**: `arn:aws:iam::123456789012:role/cmg-log-processor-github-actions-production`
5. Click **Add secret**

## Secrets Usage by Workflow

### terraform.yml
```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v6
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: eu-central-1
```
**Purpose**: Deploy infrastructure (VPC, EKS, S3, DynamoDB, SQS)

### dev.yml
```yaml
- name: Configure AWS
  uses: aws-actions/configure-aws-credentials@v6
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: eu-central-1
```
**Purpose**: Deploy application to dev EKS cluster

### production.yml
```yaml
- name: Configure AWS
  uses: aws-actions/configure-aws-credentials@v6
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: eu-central-1
```
**Purpose**: Deploy application to production EKS clusters

### reusable-build.yml
```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: ${{ env.AWS_REGION }}
```
**Purpose**: Push Docker images to ECR

### pr-checks.yml
**No secrets required** - Only runs tests and security scans

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
Assuming role: arn:aws:iam::123456789012:role/cmg-log-processor-github-actions-production
Successfully assumed role
```

## Security Best Practices

✅ **Do:**
- Use OIDC (no long-lived credentials)
- Rotate secrets if compromised
- Use environment protection rules for production
- Enable branch protection

❌ **Don't:**
- Store `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY`
- Commit secrets to code
- Share secrets across repositories
- Use same role for dev and production (optional: create separate roles)

## Troubleshooting

**Error: "Secret AWS_ROLE_ARN not found"**
- Verify secret name is exactly `AWS_ROLE_ARN` (case-sensitive)
- Check it's added as repository secret, not environment secret

**Error: "Not authorized to perform sts:AssumeRoleWithWebIdentity"**
- Verify OIDC provider exists in AWS IAM
- Check trust policy allows your GitHub repo
- Ensure `github_org` and `github_repo` match in terraform

**Error: "Access denied" when deploying**
- Verify role has necessary permissions
- Check `attach_admin_policy = true` in github-oidc module
- Or uncomment permissions in `deploy-policy.json`
