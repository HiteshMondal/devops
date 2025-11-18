################################################################################
# 7. TERRAFORM INFRASTRUCTURE
################################################################################
---
# File: infrastructure/terraform/main.tf
terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
  
  backend "s3" {
    bucket         = "mycompany-terraform-state"
    key            = "cicd/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "enterprise-cicd"
      Environment = var.environment
      ManagedBy   = "Terraform"
      CostCenter  = "Engineering"
    }
  }
}

# VPC Module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  
  name = "${var.project_name}-vpc-${var.environment}"
  cidr = var.vpc_cidr
  
  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs
  
  enable_nat_gateway   = true
  single_nat_gateway   = var.environment != "production"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true
  
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
  
  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"
  
  cluster_name    = "${var.project_name}-${var.environment}"
  cluster_version = "1.28"
  
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true
  
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }
  
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets
  
  # Node groups
  eks_managed_node_groups = {
    general = {
      name = "general-${var.environment}"
      
      instance_types = ["t3.large"]
      capacity_type  = "ON_DEMAND"
      
      min_size     = 3
      max_size     = 10
      desired_size = 3
      
      labels = {
        role = "general"
      }
      
      tags = {
        NodeGroup = "general"
      }
    }
    
    compute = {
      name = "compute-${var.environment}"
      
      instance_types = ["c5.xlarge"]
      capacity_type  = "SPOT"
      
      min_size     = 1
      max_size     = 20
      desired_size = 2
      
      labels = {
        role = "compute"
      }
      
      taints = [{
        key    = "workload"
        value  = "compute"
        effect = "NoSchedule"
      }]
      
      tags = {
        NodeGroup = "compute"
      }
    }
  }
  
  # Cluster security group rules
  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }
  
  # Node security group rules
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }
  
  tags = {
    Environment = var.environment
  }
}

# RDS PostgreSQL
module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"
  
  identifier = "${var.project_name}-db-${var.environment}"
  
  engine               = "postgres"
  engine_version       = "16.1"
  family               = "postgres16"
  major_engine_version = "16"
  instance_class       = var.db_instance_class
  
  allocated_storage     = 100
  max_allocated_storage = 500
  storage_encrypted     = true
  
  db_name  = var.db_name
  username = var.db_username
  port     = 5432
  
  multi_az               = var.environment == "production"
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [module.db_security_group.security_group_id]
  
  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  create_cloudwatch_log_group     = true
  
  backup_retention_period = var.environment == "production" ? 30 : 7
  skip_final_snapshot     = var.environment != "production"
  deletion_protection     = var.environment == "production"
  
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  
  parameters = [
    {
      name  = "autovacuum"
      value = 1
    },
    {
      name  = "client_encoding"
      value = "utf8"
    }
  ]
  
  tags = {
    Name = "${var.project_name}-db"
  }
}

# ElastiCache Redis
module "redis" {
  source  = "terraform-aws-modules/elasticache/aws"
  version = "~> 1.0"
  
  cluster_id = "${var.project_name}-redis-${var.environment}"
  
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  
  subnet_group_name  = module.vpc.elasticache_subnet_group_name
  security_group_ids = [module.redis_security_group.security_group_id]
  
  port = 6379
  
  maintenance_window = "sun:05:00-sun:06:00"
  snapshot_window    = "03:00-05:00"
  
  snapshot_retention_limit = var.environment == "production" ? 7 : 1
  automatic_failover_enabled = var.environment == "production"
  
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth_token.result
  
  tags = {
    Name = "${var.project_name}-redis"
  }
}

# Security Groups
module "db_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"
  
  name        = "${var.project_name}-db-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = module.vpc.vpc_id
  
  ingress_with_source_security_group_id = [
    {
      from_port                = 5432
      to_port                  = 5432
      protocol                 = "tcp"
      description              = "PostgreSQL access from EKS nodes"
      source_security_group_id = module.eks.node_security_group_id
    }
  ]
}

module "redis_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"
  
  name        = "${var.project_name}-redis-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = module.vpc.vpc_id
  
  ingress_with_source_security_group_id = [
    {
      from_port                = 6379
      to_port                  = 6379
      protocol                 = "tcp"
      description              = "Redis access from EKS nodes"
      source_security_group_id = module.eks.node_security_group_id
    }
  ]
}

# Random password for Redis
resource "random_password" "redis_auth_token" {
  length  = 32
  special = true
}

# Outputs
output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "rds_endpoint" {
  value     = module.rds.db_instance_endpoint
  sensitive = true
}

output "redis_endpoint" {
  value     = module.redis.cluster_cache_nodes[0].address
  sensitive = true
}
