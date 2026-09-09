########################################
# platform/infra/terraform/vpc.tf
#
# Networking only. No app-specific or Kubernetes-object resources live
# here — those are owned entirely by /platform/deployment/kubernetes and
# /monitoring, so changes there never require touching this file.
########################################

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /24s carved out of the /16 VPC CIDR: first half for public subnets
  # (EKS nodes), second half for private subnets (RDS only).
  public_subnet_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 100)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${var.app_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = local.public_subnet_cidrs
  private_subnets = local.private_subnet_cidrs

  # No NAT Gateway by default -> $0 networking cost. EKS worker nodes
  # instead run in the public subnets with public IPs (see eks.tf).
  # Set TF_VAR_enable_nat_gateway=true if you want nodes fully private.
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.enable_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required tags for the EKS + AWS Load Balancer Controller to
  # auto-discover subnets for public/internal load balancers.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  tags = local.common_tags
}
