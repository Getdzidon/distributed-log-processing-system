# Secondary region infrastructure for multi-region HA
# Deploys VPC, EKS, and networking in secondary region (eu-west-1)

# VPC for secondary region
module "vpc" {
  source = "../vpc"
  
  name_prefix        = "${var.name_prefix}-${var.environment}"
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  environment        = var.environment
}

# EKS cluster in secondary region
module "eks" {
  source = "../eks"
  
  cluster_name    = "${var.name_prefix}-${var.environment}"
  cluster_version = var.eks_cluster_version
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  environment     = var.environment
}

# Outputs
output "vpc_id" {
  description = "Secondary region VPC ID"
  value       = module.vpc.vpc_id
}

output "cluster_endpoint" {
  description = "Secondary region EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "Secondary region EKS cluster name"
  value       = module.eks.cluster_name
}
