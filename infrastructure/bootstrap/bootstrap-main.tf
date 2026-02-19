# Bootstrap Infrastructure
# One-time manual deployment for prerequisites
# Must be deployed BEFORE main Terraform infrastructure

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.33"
    }
  }
  
  # Local backend for bootstrap (no S3 dependency)
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "CMG-Log-Processor"
      Environment = "bootstrap"
      ManagedBy   = "Terraform"
    }
  }
}

# S3 bucket for Terraform state storage
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name
  
  tags = {
    Name        = "Terraform State Bucket"
    Description = "Stores Terraform state files for log-processor infrastructure"
  }
}

# Enable versioning for state file protection
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable encryption at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_lock" {
  name           = var.lock_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"
  
  attribute {
    name = "LockID"
    type = "S"
  }
  
  tags = {
    Name        = "Terraform State Lock Table"
    Description = "Prevents concurrent Terraform operations"
  }
}

# GitHub Actions OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  
  tags = {
    Name = "GitHub Actions OIDC Provider"
  }
}

# IAM role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions"
  
  assume_role_policy = templatefile("${path.module}/trust-policy.json", {
    oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
    github_org        = var.github_org
    github_repo       = var.github_repo
  })
  
  tags = {
    Name = "GitHub Actions Deployment Role"
  }
}

# Deploy policy for GitHub Actions (ECR, EKS describe, Terraform state)
resource "aws_iam_policy" "github_actions_deploy" {
  name        = "${var.project_name}-github-actions-deploy"
  description = "Policy for GitHub Actions to deploy infrastructure and applications"
  policy      = file("${path.module}/deploy-policy.json")
}

# Attach deploy policy to role
resource "aws_iam_role_policy_attachment" "github_actions_deploy" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_deploy.arn
}

# Optional: Attach AdministratorAccess for full Terraform permissions
# Set "attach_admin_policy = true" (in terraform.tfvars file) for initial setup
# Or Comment the below and uncomment sections in deploy-policy.json, then set "attach_admin_policy = false" (in terraform.tfvars file) for production
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  count      = var.attach_admin_policy ? 1 : 0
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
