###############################################################################
# variables.tf — Input Variables
# AWS Free Tier — ap-south-1 (Mumbai)
###############################################################################

#------------------------------------------------------------------------------
# Core
#------------------------------------------------------------------------------
variable "project_name" {
  description = "Short project name used in all resource names"
  type        = string
  default     = "devops-app"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.project_name))
    error_message = "project_name must be 3-24 lowercase alphanumeric characters or hyphens."
  }
}

variable "environment" {
  description = "Deployment environment (prod | staging)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging"], var.environment)
    error_message = "environment must be 'prod' or 'staging'."
  }
}

variable "owner" {
  description = "Owner tag applied to all resources"
  type        = string
  default     = "devops-team"
}

#------------------------------------------------------------------------------
# AWS Region
#------------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region — ap-south-1 is Mumbai (closest to India)"
  type        = string
  default     = "ap-south-1"
}

#------------------------------------------------------------------------------
# Networking
#------------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to use — Mumbai has ap-south-1a, 1b, 1c"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (worker nodes, RDS)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (NAT Gateway, Load Balancers)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

#------------------------------------------------------------------------------
# EKS Cluster
#------------------------------------------------------------------------------
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "devops-app-eks"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS — use latest stable"
  type        = string
  default     = "1.31"
}

# NOTE: Free Tier — t3.micro (1 vCPU, 1 GiB) qualifies for 12 months free
# For minimal viable production use t3.small or t3.medium (not free tier)
variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.micro" # Free tier eligible
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 1 # Minimise cost — scale up as needed
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes (for autoscaling)"
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "EBS disk size for worker nodes (GB) — 30 GB free tier"
  type        = number
  default     = 20
}

#------------------------------------------------------------------------------
# RDS (PostgreSQL)
# Free Tier: db.t3.micro, 20 GB storage, Single-AZ, 12 months
#------------------------------------------------------------------------------
variable "db_instance_class" {
  description = "RDS instance class — db.t3.micro is free tier eligible"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "devopsdb"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "devops_admin"
  sensitive   = true
}

variable "db_password" {
  description = "Database master password — override via TF_VAR_db_password env var"
  type        = string
  default     = "ChangeMe!Prod2024"
  sensitive   = true
}

variable "db_storage_gb" {
  description = "Allocated RDS storage in GB — 20 GB free tier"
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.3"
}

variable "db_backup_retention_days" {
  description = "Automated backup retention in days"
  type        = number
  default     = 7
}

variable "db_multi_az" {
  description = "Enable Multi-AZ for RDS (NOT free tier — enable in production)"
  type        = bool
  default     = false # Set true for real production
}

#------------------------------------------------------------------------------
# Application
#------------------------------------------------------------------------------
variable "app_name" {
  description = "Application name used in Kubernetes resources"
  type        = string
  default     = "devops-app"
}

variable "app_namespace" {
  description = "Kubernetes namespace for the application"
  type        = string
  default     = "devops-app"
}

variable "dockerhub_username" {
  description = "DockerHub username for pulling images"
  type        = string
  default     = "hiteshmondaldocker"
}

variable "docker_image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

#------------------------------------------------------------------------------
# SSH / Access
#------------------------------------------------------------------------------
variable "enable_bastion" {
  description = "Deploy a bastion host for SSH access to private resources"
  type        = bool
  default     = false # Disabled by default — costs money
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the cluster API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Restrict to your IP in production
}
