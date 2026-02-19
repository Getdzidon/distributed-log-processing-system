# AWS OIDC Setup for GitHub Actions

## Overview

GitHub Actions workflows use **OIDC (OpenID Connect)** instead of long-lived AWS credentials for enhanced security.

## Benefits

- ✅ No long-lived credentials stored in GitHub
- ✅ Temporary credentials with automatic rotation
- ✅ Fine-grained permissions per workflow
- ✅ Audit trail in AWS CloudTrail

## Setup Methods

### Method 1: Using Terraform Module (Recommended)

The repository includes a Terraform module for automated OIDC setup.

```hcl
# Add to infrastructure/terraform/main.tf
module "github_oidc" {
  source = "./modules/github-oidc"
  
  project_name  = "cmg-log-processor"
  environment   = "production"
  github_org    = "your-github-username"  # Your GitHub username (personal account)
  github_repo   = "cmg-sre-test"          # Your repository name
  
  attach_admin_policy = true  # Use with caution, only for initial setup
}

output "github_actions_role_arn" {
  value = module.github_oidc.role_arn
}
```

Deploy:
```bash
cd infrastructure/terraform
terraform apply
```

The module will output the role ARN to use in GitHub secrets.

### Method 2: Manual Setup

### Step 1: Create OIDC Provider in AWS

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### Step 2: Create IAM Role

Create `github-actions-role.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/cmg-sre-assignment:*"
        }
      }
    }
  ]
}
```

Create the role:

```bash
aws iam create-role \
  --role-name GitHubActionsRole \
  --assume-role-policy-document file://github-actions-role.json
```

### Step 3: Attach Policies

```bash
# For Terraform and EKS access
aws iam attach-role-policy \
  --role-name GitHubActionsRole \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Or create custom policy with least privilege
aws iam put-role-policy \
  --role-name GitHubActionsRole \
  --policy-name GitHubActionsPolicy \
  --policy-document file://custom-policy.json
```

### Step 4: Configure GitHub Secret

1. Go to GitHub repository **Settings → Secrets and variables → Actions**
2. Add secret:
   - Name: `AWS_ROLE_ARN`
   - Value: `arn:aws:iam::ACCOUNT_ID:role/GitHubActionsRole`

### Step 5: Test

Push to trigger workflow and verify OIDC authentication works.

## Custom Policy (Least Privilege)

Create `custom-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:*",
        "ec2:*",
        "s3:*",
        "dynamodb:*",
        "sqs:*",
        "iam:*",
        "ecr:*",
        "logs:*",
        "cloudwatch:*"
      ],
      "Resource": "*"
    }
  ]
}
```

## Verification

Check workflow logs for:
```
Assuming role: arn:aws:iam::ACCOUNT_ID:role/GitHubActionsRole
Successfully assumed role
```

## Troubleshooting

**Error: "Not authorized to perform sts:AssumeRoleWithWebIdentity"**

- Verify OIDC provider exists
- Check role trust policy matches your repository
- Ensure `token.actions.githubusercontent.com:sub` condition is correct

**Error: "Access denied"**

- Verify role has necessary permissions
- Check policy attachments

## Migration from Access Keys

1. Set up OIDC (steps above)
2. Test workflows with OIDC
3. Delete old secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
4. Rotate/delete IAM user access keys

## Security Best Practices

- ✅ Use specific repository in trust policy
- ✅ Limit to specific branches if needed
- ✅ Use least privilege IAM policies
- ✅ Enable CloudTrail for audit logging
- ✅ Regularly review role permissions
