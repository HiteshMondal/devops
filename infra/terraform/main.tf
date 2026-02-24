###############################################################################
# main.tf — Data Sources & Local Values
# AWS Free Tier — ap-south-1 (Mumbai)
###############################################################################

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "eks_node" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.cluster_version}-v*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

#------------------------------------------------------------------------------
# Local Values
#------------------------------------------------------------------------------
locals {
  cluster_name = "${var.project_name}-${var.environment}-eks"
  db_name      = replace("${var.project_name}_${var.environment}", "-", "_")

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Region      = var.aws_region
    Owner       = var.owner
  }

  # EKS cluster tags required for Load Balancer controller
  eks_cluster_tags = merge(local.common_tags, {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  })

  # Subnet tags required by AWS Load Balancer Controller
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}
