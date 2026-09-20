# platform/infra/terraform/variables.tf
#
# Every value below can be supplied via a TF_VAR_<name> environment
# variable. run.sh -> deploy_infra.sh sources the repo's .env file with
# `set -a`, so anything defined there as TF_VAR_xxx is picked up by
# Terraform automatically — no tfvars file or manual export required.

# Core / naming

variable "aws_region" {
  description = "AWS region to deploy into. Supplied by .env through run.sh."
  type        = string
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
  default     = "1.35"
}

variable "node_instance_type" {
  description = "Worker node instance type."
  type        = string
  default     = "t3.large"
}

variable "node_desired_size" {
  description = "Desired worker node count."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum worker node count."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum worker node count."
  type        = number
  default     = 3
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
  default     = "16.11"
}

variable "db_instance_class" {
  description = "RDS instance class. db.t3.micro is the cheapest general-purpose class (~$0.02/hr). Free Tier applies only if your AWS account plan includes it."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB (gp3). 20 is the RDS minimum for PostgreSQL on gp3."
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
  description = "Create a NAT Gateway so worker nodes can live in private subnets (~$0.045-0.056/hr + data)."
  type        = bool
  default     = true
}

# Distributed Cloud File System (S3 + Cross-Region Replication)

variable "enable_cloud_storage" {
  description = "Create an S3 bucket with versioning + Cross-Region Replication for distributed file storage. Free tier: 5GB S3 standard storage; replicated copy in the destination region incurs its own storage + inter-region transfer cost (~$0.02/GB), so this is opt-in."
  type        = bool
  default     = true
}

variable "cloud_storage_replica_region" {
  description = "Destination AWS region for S3 Cross-Region Replication and RDS backup replication. Must differ from var.aws_region."
  type        = string
  default     = "ap-southeast-1"
}

# Multi-Cloud (same-cloud, cross-region) Disaster Recovery

variable "enable_dr_backup" {
  description = "Uses native RDS backup replication."
  type        = bool
  default     = true
}

variable "dr_snapshot_retention_days" {
  description = "How many days to keep copied DR snapshots in the replica region before the cleanup step deletes them."
  type        = number
  default     = 7
}

# variables.tf
variable "console_principal_arn" {
  description = "IAM user/role ARN for console access to EKS resources. Leave empty if you use the same identity as your CLI credentials."
  type        = string
  default     = ""
}
