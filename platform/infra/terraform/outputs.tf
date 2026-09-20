########################################
# platform/infra/terraform/outputs.tf
########################################

output "aws_region" {
  description = "AWS region resources were deployed into."
  value       = var.aws_region
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "eks_cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the new cluster (used by deploy_kubernetes.sh)."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "db_endpoint" {
  description = "RDS connection endpoint (host:port)."
  value       = aws_db_instance.this.endpoint
}

output "db_host" {
  description = "RDS hostname only, for DB_HOST."
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "RDS port, for DB_PORT."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Database name, for DB_NAME."
  value       = aws_db_instance.this.db_name
}

output "estimated_free_tier_note" {
  description = "Cost reminder."
  value       = "EKS control plane is $0.10/hr on a STANDARD-support version but $0.60/hr once a version enters extended support (check kubernetes_version). Worker nodes, NAT gateway (if enabled), NLB and RDS add roughly $0.20-0.25/hr. Free Tier eligibility depends on your account plan. Run destroy when you are done."
}

output "postgres_backup_role_arn" {
  description = "IRSA role ARN for the postgres-backup CronJob ServiceAccount (null when enable_cloud_storage=false)."
  value       = var.enable_cloud_storage ? aws_iam_role.postgres_backup[0].arn : null
}

output "backup_bucket_name" {
  description = "S3 bucket name for application backups."
  value       = var.enable_cloud_storage ? aws_s3_bucket.files_primary[0].bucket : null
}
