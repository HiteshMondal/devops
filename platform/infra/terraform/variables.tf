########################################
# platform/infra/terraform/variables.tf
#
# Every value below can be supplied via a TF_VAR_<name> environment
# variable. run.sh -> deploy_infra.sh sources the repo's .env file with
# `set -a`, so anything defined there as TF_VAR_xxx is picked up by
# Terraform automatically — no tfvars file or manual export required.
########################################

# Core / naming

variable "aws_region" {
  description = "AWS region to deploy into. Free-tier resources exist in every region, but pick one close to you."
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Application name, used as a prefix for all resource names/tags. Mirrors APP_NAME in .env."
  type        = string
  default     = "devops-app"
}

variable "environment" {
  description = "Deployment environment label. Infra only ever runs for production (see run.sh)."
  type        = string
  default     = "production"
}

# Networking

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets across (2 is the practical minimum for EKS/RDS)."
  type        = number
  default     = 2
}

# EKS / compute

variable "kubernetes_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.30"
}

variable "node_instance_type" {
  description = "Worker node instance type. t3.micro/t2.micro are AWS Free Tier eligible (750 hrs/month for 12 months on a new account)."
  type        = string
  default     = "t3.micro"
}

variable "node_desired_size" {
  description = "Desired worker node count. Keep at 1 to stay inside the Free Tier's 750 instance-hours/month."
  type        = number
  default     = 1
}

variable "node_min_size" {
  description = "Minimum worker node count."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum worker node count."
  type        = number
  default     = 2
}

variable "app_port" {
  description = "Port the application container listens on. Mirrors APP_PORT in .env; used for the worker-node security group rule."
  type        = number
  default     = 8000
}

# RDS / database

variable "db_engine" {
  description = "RDS database engine."
  type        = string
  default     = "postgres"
}

variable "db_engine_version" {
  description = "RDS engine version."
  type        = string
  default     = "16.4"
}

variable "db_instance_class" {
  description = "RDS instance class. db.t3.micro/db.t4g.micro are AWS Free Tier eligible (750 hrs/month for 12 months on a new account)."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB. 20GB gp2/gp3 is the Free Tier ceiling."
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Database name. Mirrors DB_NAME in .env."
  type        = string
  default     = "devopsdb"
}

variable "db_port" {
  description = "Database port. Mirrors DB_PORT in .env."
  type        = number
  default     = 5432
}

variable "db_username" {
  description = "Database master username. Mirrors DB_USERNAME in .env."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_username) > 0
    error_message = "db_username is required — set DB_USERNAME / TF_VAR_db_username in .env."
  }
}

variable "db_password" {
  description = "Database master password. Mirrors DB_PASSWORD in .env. No default on purpose — must be supplied."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "db_password must be at least 8 characters — set DB_PASSWORD / TF_VAR_db_password in .env."
  }
}

variable "db_multi_az" {
  description = "Enable Multi-AZ RDS failover. Costs extra and is NOT Free Tier eligible — off by default."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Automated backup retention period in days."
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "Prevent accidental terraform destroy of the database. Recommended true for real production use."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. Keep true for disposable free-tier/dev environments."
  type        = bool
  default     = true
}

# Cost-control switches

variable "enable_nat_gateway" {
  description = "Create a NAT Gateway for private-subnet egress. NAT Gateway is NOT Free Tier eligible (~$0.045/hr + data). Off by default; worker nodes run in public subnets with public IPs instead to keep this deployable at $0 infra cost beyond the EKS control plane."
  type        = bool
  default     = false
}

# Distributed Cloud File System (S3 + Cross-Region Replication)

variable "enable_cloud_storage" {
  description = "Create an S3 bucket with versioning + Cross-Region Replication for distributed file storage. Free tier: 5GB S3 standard storage; replicated copy in the destination region incurs its own storage + inter-region transfer cost (~$0.02/GB), so this is opt-in."
  type        = bool
  default     = false
}

variable "cloud_storage_replica_region" {
  description = "Destination AWS region for S3 Cross-Region Replication. Must differ from var.aws_region."
  type        = string
  default     = "us-west-2"
}

# Self-Healing Infrastructure (CloudWatch Alarms -> Lambda remediation)

variable "enable_self_healing" {
  description = "Deploy CloudWatch Alarms + a Python Lambda that automatically remediates unhealthy EKS worker nodes (terminate -> ASG replaces) and RDS failures (reboot). Lambda free tier (1M requests + 400,000 GB-s/month) covers this comfortably, so cost stays ~$0."
  type        = bool
  default     = false
}

# Multi-Cloud (same-cloud, cross-region) Disaster Recovery

variable "enable_dr_backup" {
  description = "Deploy a scheduled Lambda (via EventBridge) that snapshots RDS and copies the snapshot to var.cloud_storage_replica_region for disaster recovery. Snapshot storage beyond the 20GB Free Tier allocation is billed (~$0.095/GB-month), so keep retention short via dr_snapshot_retention_days."
  type        = bool
  default     = false
}

variable "dr_backup_schedule_expression" {
  description = "EventBridge schedule expression for the DR snapshot job."
  type        = string
  default     = "rate(1 day)"
}

variable "dr_snapshot_retention_days" {
  description = "How many days to keep copied DR snapshots in the replica region before the cleanup step (run inside the same Lambda) deletes them."
  type        = number
  default     = 7
}
