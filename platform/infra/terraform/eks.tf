########################################
# platform/infra/terraform/eks.tf
#
# Provisions only the cluster + node group. It never creates Kubernetes
# application objects (Deployments, Services, etc.) — those are applied
# separately by platform/deployment/kubernetes/deploy_kubernetes.sh via
# kubectl/kustomize. That keeps /app changes from ever requiring a
# terraform apply.
########################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id                          = module.vpc.vpc_id
  enable_irsa                     = true
  subnet_ids                      = var.enable_nat_gateway ? module.vpc.private_subnets : module.vpc.public_subnets
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  cluster_enabled_log_types = ["api", "authenticator"]

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni = {
      most_recent          = true
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }
    metrics-server = { most_recent = true }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      # Public IP only matters when nodes sit in public subnets.
      associate_public_ip_address = !var.enable_nat_gateway

      labels = {
        role = "app"
      }

      tags = local.common_tags

      node_repair_config = { enabled = true }
    }
  }

  access_entries = {
    for k, arn in { console = var.console_principal_arn } : k => {
      principal_arn         = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    } if arn != ""
  }

  # Grants the identity running `terraform apply` cluster-admin so the
  # very first kubectl/kustomize step in deploy_kubernetes.sh works
  # without any extra IAM wiring.
  enable_cluster_creator_admin_permissions = true

  tags                                   = local.common_tags
  cloudwatch_log_group_retention_in_days = 7
}

# Allows the app's pods (via the worker node security group) to reach
# the RDS instance on the database port, and lets the EKS-managed
# ingress/NLB reach pods on the app port. Kept here (not in vpc.tf)
# because it depends on the node security group EKS creates.
resource "aws_security_group_rule" "nodes_app_port_ingress" {
  description              = "Allow traffic to the app port from within the node security group (NLB/ingress health checks and inter-pod traffic)"
  type                     = "ingress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  security_group_id        = module.eks.node_security_group_id
  source_security_group_id = module.eks.node_security_group_id
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name             = "${local.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = local.common_tags
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
  depends_on               = [module.eks]
}
