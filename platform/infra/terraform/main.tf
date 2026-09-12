########################################
# platform/infra/terraform/main.tf
#
# Root wiring only: required providers/backend, data sources, and shared
# locals. Actual resources live in their own files (vpc.tf, eks.tf, rds.tf)
# so each concern can be read/changed independently.
########################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  common_tags = {
    Project     = var.app_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  cluster_name = "${var.app_name}-${var.environment}"
}
