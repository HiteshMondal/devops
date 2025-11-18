# terraform/environments/dev/variables.tf

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Project owner"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "engineering"
}

# VPC Variables
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "database_subnet_cidrs" {
  description = "Database subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}

# Compute Variables
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro" # Free tier eligible
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "asg_min_size" {
  description = "Auto Scaling Group minimum size"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Auto Scaling Group maximum size"
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Auto Scaling Group desired capacity"
  type        = number
  default     = 2
}

variable "app_port" {
  description = "Application port"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Health check path"
  type        = string
  default     = "/health"
}

variable "ssl_certificate_arn" {
  description = "SSL certificate ARN for HTTPS"
  type        = string
  default     = ""
}

# Database Variables
variable "db_name" {
  description = "Database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "dbadmin"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro" # Free tier eligible
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20 # Free tier: 20GB
}

variable "db_max_allocated_storage" {
  description = "Maximum allocated storage for autoscaling"
  type        = number
  default     = 100
}

variable "db_multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = false # Set to true for production
}

variable "db_backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "db_backup_window" {
  description = "Preferred backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "db_maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
  default     = "mon:04:00-mon:05:00"
}

variable "db_performance_insights" {
  description = "Enable Performance Insights"
  type        = bool
  default     = false
}

variable "db_enhanced_monitoring" {
  description = "Enable Enhanced Monitoring"
  type        = bool
  default     = false
}

variable "db_deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = false # Set to true for production
}

variable "db_skip_final_snapshot" {
  description = "Skip final snapshot on deletion"
  type        = bool
  default     = true # Set to false for production
}

# Cache Variables
variable "cache_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro" # Free tier eligible
}

variable "cache_num_nodes" {
  description = "Number of cache nodes"
  type        = number
  default     = 1
}

variable "cache_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"
}

variable "cache_parameter_group_family" {
  description = "Cache parameter group family"
  type        = string
  default     = "redis7"
}

variable "cache_automatic_failover" {
  description = "Enable automatic failover"
  type        = bool
  default     = false # Set to true for production with multiple nodes
}

# S3 Variables
variable "s3_enable_versioning" {
  description = "Enable S3 versioning"
  type        = bool
  default     = true
}

variable "s3_enable_lifecycle" {
  description = "Enable S3 lifecycle policies"
  type        = bool
  default     = true
}

variable "s3_lifecycle_glacier_days" {
  description = "Days until transition to Glacier"
  type        = number
  default     = 90
}

variable "s3_lifecycle_expiration_days" {
  description = "Days until object expiration"
  type        = number
  default     = 365
}

# Monitoring Variables
variable "alert_email" {
  description = "Email for alerts"
  type        = string
}

variable "enable_sns_notifications" {
  description = "Enable SNS notifications"
  type        = bool
  default     = true
}