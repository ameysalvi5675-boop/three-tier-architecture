# ==============================================================
# Jerney EKS Cluster - Managed Node Groups
# ==============================================================

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

# ---- VPC ----
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true # Cost-saving for dev; use one per AZ for prod

  # Tags required for EKS to discover subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

# ---- EKS Cluster (with Managed Node Groups) ----
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Networking
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Security: enable private endpoint, public for initial kubectl access
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Auth mode for API access
  authentication_mode = "API"

  # Security: envelope encryption for secrets at rest
  cluster_encryption_config = {
    resources = ["secrets"]
  }

  # Security: enable logging
  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  # Allow current caller (your IAM user/role) to manage the cluster
  enable_cluster_creator_admin_permissions = true

  # ---- Managed Node Groups ----
  eks_managed_node_groups = {
    general_purpose = {
      name            = "general-purpose-nodes"
      min_size        = 1
      max_size        = 3
      desired_size    = 2 # This will create 2 nodes immediately

      instance_types  = ["t3.medium"] # Cost-effective for dev
      disk_size       = 20

      # Tags for workload scheduling
      labels = {
        Environment = var.environment
        Role        = "general-purpose"
      }

      tags = {
        "ManagedNodeGroup" = "general-purpose"
      }
    }
  }
}
