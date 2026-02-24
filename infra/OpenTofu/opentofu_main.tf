###############################################################################
# opentofu_main.tf — Oracle Cloud Infrastructure (OCI) Provider
# OpenTofu >= 1.6.0
#
# Oracle Cloud Free Tier (Always Free — no 12-month limit):
#   • 2x AMD VM.Standard.E2.1.Micro  (1 OCPU, 1 GB RAM each)  ← We use these
#   • 4x ARM Ampere A1 Compute       (1-4 OCPU, 6-24 GB RAM)  ← OKE nodes
#   • 2x Block Volumes (200 GB total)
#   • 1x Autonomous Database (20 GB)
#   • 10 GB Object Storage
#   • Load Balancer: 10 Mbps (1 free)
#   • Outbound data: 10 GB/month free
#
# India-compatible Regions:
#   • ap-mumbai-1    — Mumbai (closest to India, recommended)
#   • ap-hyderabad-1 — Hyderabad (second India region)
#   • ap-singapore-1 — Singapore (APAC alternative)
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Uncomment to use OCI Object Storage backend for remote state
  # backend "http" {
  #   address        = "https://objectstorage.ap-mumbai-1.oraclecloud.com/p/.../n/.../b/tfstate/o/devops-app.tfstate"
  #   update_method  = "PUT"
  # }
}

#------------------------------------------------------------------------------
# OCI Provider — API Key Authentication
# Set these via environment variables or terraform.tfvars (NEVER commit secrets)
#   export TF_VAR_tenancy_ocid="ocid1.tenancy.oc1..."
#   export TF_VAR_user_ocid="ocid1.user.oc1..."
#   export TF_VAR_fingerprint="aa:bb:cc..."
#   export TF_VAR_private_key_path="/path/to/oci_api_key.pem"
#------------------------------------------------------------------------------
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.oci_region
}

#------------------------------------------------------------------------------
# Availability Domains
#------------------------------------------------------------------------------
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

#------------------------------------------------------------------------------
# Local Values
#------------------------------------------------------------------------------
locals {
  # Always Free ARM Ampere A1 shape for OKE nodes
  # arm_shape = "VM.Standard.A1.Flex"   # 4 OCPU, 24 GB RAM total (always free)
  # amd_shape = "VM.Standard.E2.1.Micro" # 2 x micro VMs (always free)

  cluster_name = "${var.project_name}-${var.environment}-oke"
  db_name      = replace("${var.project_name}_${var.environment}", "-", "_")

  common_tags = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "OpenTofu"
    owner       = var.owner
  }

  # OCI freeform tags (must be string map)
  freeform_tags = {
    "Project"     = var.project_name
    "Environment" = var.environment
    "ManagedBy"   = "OpenTofu"
  }
}

#------------------------------------------------------------------------------
# Compartment — logical isolation boundary in OCI
# Use root tenancy OCID for free tier (or create a dedicated compartment)
#------------------------------------------------------------------------------
resource "oci_identity_compartment" "main" {
  compartment_id = var.tenancy_ocid
  name           = "${var.project_name}-${var.environment}"
  description    = "${var.project_name} ${var.environment} compartment — managed by OpenTofu"
  enable_delete  = false

  freeform_tags = local.freeform_tags
}
