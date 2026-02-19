terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.33"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
  }
  
  # Backend stores state in S3 with workspace-specific paths
  # Workspaces: dev, production
  # State files:
  #   - s3://cmg-terraform-state/env:/dev/log-processor/terraform.tfstate
  #   - s3://cmg-terraform-state/env:/production/log-processor/terraform.tfstate
  backend "s3" {
    bucket         = "cmg-terraform-state"
    key            = "log-processor/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "CMG-Log-Processor"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
  
  default_tags {
    tags = {
      Project     = "CMG-Log-Processor"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

locals {
  # Environment-specific naming: cmg-log-processor-dev or cmg-log-processor-production
  name_prefix = "cmg-log-processor-${var.environment}"
  
  common_tags = {
    Project     = "CMG-Log-Processor"
    Environment = var.environment  # dev or production
    ManagedBy   = "Terraform"
  }
}

# VPC and Networking
module "vpc" {
  source = "./modules/vpc"
  
  name_prefix         = local.name_prefix
  vpc_cidr            = var.vpc_cidr
  availability_zones  = var.availability_zones
  environment         = var.environment
}

# EKS Cluster
module "eks" {
  source = "./modules/eks"
  
  cluster_name       = "${local.name_prefix}-cluster"
  cluster_version    = var.eks_cluster_version
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  environment        = var.environment
}

# SQS Queue
module "sqs" {
  source = "./modules/sqs"
  
  queue_name          = "${local.name_prefix}-queue"
  visibility_timeout  = 300
  message_retention   = 1209600  # 14 days
  environment         = var.environment
}

# S3 Bucket for raw logs
module "s3" {
  source = "./modules/s3"
  
  bucket_name         = "${local.name_prefix}-raw-logs"
  enable_replication  = var.enable_multi_region
  replication_region  = var.secondary_region
  environment         = var.environment
}

# DynamoDB for processed metrics (application data)
# Note: Different from bootstrap DynamoDB table which is for Terraform state locking
module "dynamodb" {
  source = "./modules/dynamodb"
  
  table_name          = "${local.name_prefix}-metrics"
  enable_global_table = var.enable_multi_region
  replica_regions     = var.enable_multi_region ? [var.secondary_region] : []
  environment         = var.environment
}

# IAM Roles for Service Accounts (IRSA)
module "irsa" {
  source = "./modules/irsa"
  
  cluster_name           = module.eks.cluster_name
  oidc_provider_arn      = module.eks.oidc_provider_arn
  namespace              = "log-processing"
  service_account_name   = "log-processor"
  s3_bucket_arn          = module.s3.bucket_arn
  sqs_queue_arn          = module.sqs.queue_arn
  dynamodb_table_arn     = module.dynamodb.table_arn
}

# Secondary Region (for HA)
# Uncomment to enable multi-region deployment
# Note: Requires additional EKS cluster in secondary region

# module "secondary_region" {
#   count  = var.enable_multi_region ? 1 : 0
#   source = "./modules/secondary-region"
#   
#   providers = {
#     aws = aws.secondary
#   }
#   
#   name_prefix        = local.name_prefix
#   vpc_cidr           = var.secondary_vpc_cidr
#   availability_zones = var.secondary_availability_zones
#   environment        = var.environment
# }


# Route53 Health Checks and Failover
# Uncomment to enable DNS-based failover
# Note: Requires Route53 hosted zone for domain_name

# module "route53" {
#   count  = var.enable_multi_region ? 1 : 0
#   source = "./modules/route53"
#   
#   domain_name       = var.domain_name
#   primary_endpoint  = module.eks.cluster_endpoint
#   secondary_endpoint = var.enable_multi_region ? module.secondary_region[0].cluster_endpoint : ""
#   environment       = var.environment
# }
