###############################################################################
# opentofu_variables.tf — Input Variables
# Oracle Cloud Infrastructure — Always Free Tier
# Region: ap-mumbai-1 (Mumbai) | Fallback: ap-hyderabad-1
###############################################################################

#------------------------------------------------------------------------------
# OCI Authentication — NEVER hardcode these values
# Pass via environment variables: export TF_VAR_tenancy_ocid="..."
#------------------------------------------------------------------------------
variable "tenancy_ocid" {
  description = "OCI Tenancy OCID — found in OCI Console → Profile → Tenancy"
  type        = string
  sensitive   = true
}

variable "user_ocid" {
  description = "OCI User OCID — found in OCI Console → Profile"
  type        = string
  sensitive   = true
}

variable "fingerprint" {
  description = "API key fingerprint — generated when uploading API key"
  type        = string
  sensitive   = true
}

variable "private_key_path" {
  description = "Path to OCI API private key file"
  type        = string
  default     = "~/.oci/oci_api_key.pem"
}

#------------------------------------------------------------------------------
# Core
#------------------------------------------------------------------------------
variable "project_name" {
  description = "Short project name used in all resource names"
  type        = string
  default     = "devops-app"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.project_name))
    error_message = "project_name must be 3-24 lowercase alphanumeric or hyphens."
  }
}

variable "environment" {
  description = "Deployment environment"
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
# OCI Region
#------------------------------------------------------------------------------
variable "oci_region" {
  description = <<-EOT
    OCI region identifier.
    India options:
      ap-mumbai-1    — Mumbai (recommended, lowest latency from India)
      ap-hyderabad-1 — Hyderabad (second India region)
    Other APAC:
      ap-singapore-1 — Singapore
      ap-sydney-1    — Sydney
  EOT
  type    = string
  default = "ap-mumbai-1"

  validation {
    condition = contains([
      "ap-mumbai-1", "ap-hyderabad-1", "ap-singapore-1",
      "ap-sydney-1", "ap-tokyo-1", "ap-osaka-1"
    ], var.oci_region)
    error_message = "Use a valid APAC OCI region identifier."
  }
}

#------------------------------------------------------------------------------
# Networking
#------------------------------------------------------------------------------
variable "vcn_cidr" {
  description = "CIDR block for the Virtual Cloud Network (VCN)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR (Load Balancer, Bastion)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_node_subnet_cidr" {
  description = "Private subnet CIDR for OKE worker nodes"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_pod_subnet_cidr" {
  description = "Private subnet CIDR for OKE pod networking (VCN-native pod networking)"
  type        = string
  default     = "10.0.3.0/24"
}

variable "private_db_subnet_cidr" {
  description = "Private subnet CIDR for Autonomous Database"
  type        = string
  default     = "10.0.4.0/24"
}

#------------------------------------------------------------------------------
# OKE Cluster (Oracle Kubernetes Engine)
#------------------------------------------------------------------------------
variable "kubernetes_version" {
  description = "Kubernetes version for OKE — use latest stable"
  type        = string
  default     = "v1.31.1"
}

# Always Free: VM.Standard.A1.Flex — ARM Ampere
# Free allocation: 4 OCPU + 24 GB RAM total (can be split across instances)
variable "node_shape" {
  description = "OCI compute shape for OKE worker nodes"
  type        = string
  default     = "VM.Standard.A1.Flex" # Always Free ARM
}

variable "node_ocpus" {
  description = "OCPUs per worker node (Always Free: 4 total)"
  type        = number
  default     = 2 # 2 nodes × 2 OCPU = 4 total (free limit)
}

variable "node_memory_gb" {
  description = "Memory (GB) per worker node (Always Free: 24 GB total)"
  type        = number
  default     = 12 # 2 nodes × 12 GB = 24 GB total (free limit)
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2 # Stay within Always Free limits
}

variable "node_boot_volume_gb" {
  description = "Boot volume size for worker nodes (GB)"
  type        = number
  default     = 50 # Part of 200 GB Always Free block storage
}

#------------------------------------------------------------------------------
# Autonomous Database (Always Free)
# 20 GB storage, shared ECPU, no time limit
#------------------------------------------------------------------------------
variable "adb_display_name" {
  description = "Autonomous Database display name"
  type        = string
  default     = "DevOpsAppDB"
}

variable "adb_db_name" {
  description = "Autonomous Database name (alphanumeric, max 14 chars)"
  type        = string
  default     = "devopsappdb"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,13}$", var.adb_db_name))
    error_message = "ADB name must start with a letter, be alphanumeric, max 14 chars."
  }
}

variable "adb_admin_password" {
  description = "Autonomous Database ADMIN password — override via TF_VAR_adb_admin_password"
  type        = string
  default     = "ChangeMe!Prod2024#"
  sensitive   = true

  validation {
    condition     = can(regex("^(?=.*[A-Z])(?=.*[a-z])(?=.*[0-9])(?=.*[^a-zA-Z0-9]).{12,}$", var.adb_admin_password))
    error_message = "Password must have uppercase, lowercase, number, special char, min 12 chars."
  }
}

variable "adb_storage_tb" {
  description = "Autonomous Database storage (TB) — 0.02 TB = 20 GB (free limit)"
  type        = number
  default     = 1 # Minimum billing unit; always-free is enforced via is_free_tier
}

#------------------------------------------------------------------------------
# SSH Access
#------------------------------------------------------------------------------
variable "ssh_public_key_path" {
  description = "Path to SSH public key for OKE node access"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

#------------------------------------------------------------------------------
# Application
#------------------------------------------------------------------------------
variable "app_name" {
  description = "Application name"
  type        = string
  default     = "devops-app"
}

variable "app_namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "devops-app"
}

variable "dockerhub_username" {
  description = "DockerHub username"
  type        = string
  default     = "hiteshmondaldocker"
}

variable "docker_image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}
