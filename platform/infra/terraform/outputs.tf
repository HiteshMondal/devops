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
  description = "Reminder about what is and isn't covered by AWS Free Tier."
  value       = "EKS control plane (~$0.10/hr) is NOT Free Tier eligible and is the one guaranteed cost. Worker node (t3.micro/t2.micro) and RDS (db.t3.micro/db.t4g.micro, <=20GB) are Free Tier eligible for a new AWS account's first 12 months only."
}

output "postgres_backup_role_arn" {
  description = "IRSA role ARN for the postgres-backup CronJob ServiceAccount."
  value       = aws_iam_role.postgres_backup.arn
}

output "backup_bucket_name" {
  description = "S3 bucket name for application backups."
  value       = var.enable_cloud_storage ? aws_s3_bucket.files_primary[0].bucket : null
}
