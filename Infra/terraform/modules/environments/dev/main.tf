# terraform/environments/dev/main.tf
# Development environment infrastructure

terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "s3" {
    # Configure in backend.tf or via CLI
    # bucket         = "your-terraform-state-bucket"
    # key            = "dev/terraform.tfstate"
    # region         = "us-east-1"
    # encrypt        = true
    # dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Owner       = var.owner
      CostCenter  = var.cost_center
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Local variables
locals {
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# VPC Module
module "vpc" {
  source = "../../modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = local.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  enable_flow_logs     = var.enable_flow_logs

  tags = local.common_tags
}

# Security Groups Module
module "security_groups" {
  source = "../../modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr

  tags = local.common_tags
}

# Compute Module (EC2 + ALB + ASG)
module "compute" {
  source = "../../modules/compute"

  project_name         = var.project_name
  environment          = var.environment
  aws_region           = var.aws_region
  vpc_id               = module.vpc.vpc_id
  public_subnet_ids    = module.vpc.public_subnet_ids
  private_subnet_ids   = module.vpc.private_subnet_ids
  
  ami_id                     = data.aws_ami.amazon_linux_2.id
  instance_type              = var.instance_type
  key_name                   = var.key_name
  alb_security_group_id      = module.security_groups.alb_security_group_id
  instance_security_group_id = module.security_groups.instance_security_group_id
  
  asg_min_size         = var.asg_min_size
  asg_max_size         = var.asg_max_size
  asg_desired_capacity = var.asg_desired_capacity
  
  app_port           = var.app_port
  health_check_path  = var.health_check_path
  ssl_certificate_arn = var.ssl_certificate_arn

  tags = local.common_tags
}

# Database Module (RDS)
module "database" {
  source = "../../modules/database"

  project_name            = var.project_name
  environment             = var.environment
  db_subnet_group_name    = module.vpc.db_subnet_group_name
  db_security_group_id    = module.security_groups.db_security_group_id
  availability_zones      = local.availability_zones
  
  db_name                 = var.db_name
  db_username             = var.db_username
  db_engine_version       = var.db_engine_version
  db_instance_class       = var.db_instance_class
  db_allocated_storage    = var.db_allocated_storage
  multi_az                = var.db_multi_az
  
  backup_retention_period = var.db_backup_retention_period
  backup_window          = var.db_backup_window
  maintenance_window     = var.db_maintenance_window
  
  performance_insights_enabled = var.db_performance_insights
  enhanced_monitoring_enabled  = var.db_enhanced_monitoring
  deletion_protection          = var.db_deletion_protection
  skip_final_snapshot         = var.db_skip_final_snapshot

  tags = local.common_tags
}

# ElastiCache Module (Redis)
module "cache" {
  source = "../../modules/cache"

  project_name               = var.project_name
  environment                = var.environment
  subnet_group_name          = module.vpc.elasticache_subnet_group_name
  cache_security_group_id    = module.security_groups.cache_security_group_id
  
  node_type                  = var.cache_node_type
  num_cache_nodes            = var.cache_num_nodes
  engine_version             = var.cache_engine_version
  parameter_group_family     = var.cache_parameter_group_family
  
  automatic_failover_enabled = var.cache_automatic_failover

  tags = local.common_tags
}

# S3 Module (Application storage)
module "storage" {
  source = "../../modules/storage"

  project_name = var.project_name
  environment  = var.environment
  
  enable_versioning       = var.s3_enable_versioning
  enable_lifecycle        = var.s3_enable_lifecycle
  lifecycle_glacier_days  = var.s3_lifecycle_glacier_days
  lifecycle_expiration_days = var.s3_lifecycle_expiration_days

  tags = local.common_tags
}

# Monitoring Module (CloudWatch)
module "monitoring" {
  source = "../../modules/monitoring"

  project_name = var.project_name
  environment  = var.environment
  
  alb_arn                 = module.compute.alb_arn
  asg_name                = module.compute.asg_name
  db_instance_identifier  = module.database.db_instance_id
  cache_cluster_id        = module.cache.cache_cluster_id
  
  alert_email             = var.alert_email
  enable_sns_notifications = var.enable_sns_notifications

  tags = local.common_tags
}