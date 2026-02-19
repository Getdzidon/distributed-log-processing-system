# Bootstrap Infrastructure

## Purpose

This directory contains **one-time manual setup** for:
1. **S3 backend** - Terraform state storage
2. **DynamoDB table** - State locking
3. **GitHub OIDC** - GitHub Actions authentication

**Deploy this ONCE before running main Terraform infrastructure.**

## Prerequisites

- AWS CLI configured with credentials
- Terraform >= 1.5
- GitHub repository created

## Deployment

### Step 1: Update Variables

Edit `terraform.tfvars`:

```hcl
github_org  = "your-github-username"  # Replace with your GitHub username
github_repo = "cmg-sre-test"          # Replace with your repository name

# Set to false for production (uncomment sections in deploy-policy.json first)
attach_admin_policy = true
```

### Step 2: Deploy Bootstrap

```bash
cd infrastructure/bootstrap

# Initialize Terraform (uses local backend)
terraform init

# Review what will be created
terraform plan

# Deploy
terraform apply
```

## Resources Created

Bootstrap creates these resources:

| Resource | Name | Purpose |
|----------|------|---------|
| S3 Bucket | `cmg-terraform-state` | Stores Terraform state files |
| DynamoDB Table | `terraform-lock` | Prevents concurrent Terraform runs |
| OIDC Provider | GitHub Actions | Allows GitHub to authenticate to AWS |
| IAM Role | `cmg-log-processor-github-actions` | Role assumed by GitHub Actions |

**Important**: The S3 bucket name (`cmg-terraform-state`) and DynamoDB table name (`terraform-lock`) are hardcoded in `infrastructure/terraform/main.tf` backend configuration. If you change these names in `terraform.tfvars`, you must also update the backend block in `infrastructure/terraform/main.tf`.

### Step 3: Save Outputs

```bash
# Get the GitHub Actions role ARN
terraform output github_actions_role_arn

# Example output:
# arn:aws:iam::123456789012:role/cmg-log-processor-github-actions
```

### Step 4: Add Secret to GitHub

1. Go to GitHub repository → **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Name: `AWS_ROLE_ARN`
4. Value: (paste the role ARN from step 3)
5. Click **Add secret**

### Step 5: Trigger CI/CD Deployment

Now that bootstrap is complete, push your code to GitHub to trigger automated deployment:

```bash
# Commit and push to main branch
git add .
git commit -m "Initial infrastructure setup"
git push origin main
```

**What happens next:**
1. GitHub Actions workflow triggers automatically
2. Workflow authenticates to AWS using OIDC (the role you just created)
3. Terraform initializes with S3 backend (the bucket you just created)
4. Infrastructure deploys to **dev** environment automatically
5. For **production**, manually trigger the workflow from GitHub Actions UI

**Manual deployment (optional):**

If you need to deploy manually for testing:

```bash
cd ../terraform

# Initialize with S3 backend
terraform init

# Create and select dev workspace
terraform workspace new dev
terraform workspace select dev

# Deploy to dev
terraform apply -var-file=environments/dev.tfvars
```

## State Management

Bootstrap uses **local backend** (stores state in `terraform.tfstate` file).

**Important**: Keep this file safe! It contains the state for your bootstrap resources.

## Cleanup

To destroy bootstrap resources (only do this if removing entire project):

```bash
cd infrastructure/bootstrap
terraform destroy
```

**Warning**: This will prevent GitHub Actions from working and remove Terraform state storage!

## Troubleshooting

**Error: "Bucket already exists"**
- Change `state_bucket_name` in terraform.tfvars to a unique name
- S3 bucket names must be globally unique

**Error: "Table already exists"**
- Change `lock_table_name` in terraform.tfvars

**GitHub Actions can't authenticate**
- Verify `github_org` and `github_repo` match exactly
- Check `AWS_ROLE_ARN` secret is added to GitHub
- Ensure OIDC provider was created successfully

## Next Steps

After bootstrap:
1. ✅ Main Terraform infrastructure can use S3 backend
2. ✅ GitHub Actions workflows can authenticate to AWS
3. ✅ State locking prevents concurrent modifications
4. ✅ Ready for automated CI/CD deployments
