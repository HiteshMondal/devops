###############################################################################
# outputs.tf — Terraform Output Values
# AWS Free Tier — ap-south-1 (Mumbai)
###############################################################################

#------------------------------------------------------------------------------
# VPC
#------------------------------------------------------------------------------
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS nodes, RDS)"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (Load Balancers, NAT GW)"
  value       = aws_subnet.public[*].id
}

output "nat_gateway_ip" {
  description = "NAT Gateway public IP (for whitelisting)"
  value       = aws_eip.nat[0].public_ip
}

#------------------------------------------------------------------------------
# EKS
#------------------------------------------------------------------------------
output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "EKS Kubernetes version"
  value       = aws_eks_cluster.main.version
}

output "cluster_oidc_issuer_url" {
  description = "EKS cluster OIDC issuer URL (for IRSA)"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "cluster_oidc_provider_arn" {
  description = "OIDC provider ARN (for IRSA)"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "node_group_arn" {
  description = "EKS managed node group ARN"
  value       = aws_eks_node_group.main.arn
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for Cluster Autoscaler (use in Helm values)"
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "aws_lbc_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller (use in Helm values)"
  value       = aws_iam_role.aws_lbc.arn
}

output "kubeconfig_command" {
  description = "AWS CLI command to update kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

#------------------------------------------------------------------------------
# RDS
#------------------------------------------------------------------------------
output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.identifier
}

output "db_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.address
  sensitive   = true
}

output "db_port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.main.db_name
}

output "db_secret_arn" {
  description = "Secrets Manager ARN containing DB credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "db_secret_name" {
  description = "Secrets Manager secret name"
  value       = aws_secretsmanager_secret.db_credentials.name
}

#------------------------------------------------------------------------------
# Security Groups
#------------------------------------------------------------------------------
output "eks_cluster_sg_id" {
  description = "EKS cluster security group ID"
  value       = aws_security_group.eks_cluster.id
}

output "eks_nodes_sg_id" {
  description = "EKS worker node security group ID"
  value       = aws_security_group.eks_nodes.id
}

output "rds_sg_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}

#------------------------------------------------------------------------------
# AWS Account Info
#------------------------------------------------------------------------------
output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

#------------------------------------------------------------------------------
# Cost Estimate (informational)
#------------------------------------------------------------------------------
output "cost_estimate" {
  description = "Approximate monthly cost (USD) — Free tier deductions apply for 12 months"
  value = {
    eks_control_plane = "$73.00 (NOT free tier)"
    nat_gateway       = "~$32.00 + $0.045/GB data (NOT free tier)"
    ec2_t3_micro      = "$0.00 (free tier: 750 hrs/month)"
    rds_db_t3_micro   = "$0.00 (free tier: 750 hrs/month)"
    ebs_storage_20gb  = "$0.00 (free tier: 30 GB gp2)"
    data_transfer     = "First 100 GB free"
    note              = "After 12 months EKS + NAT Gateway dominate costs"
  }
}
