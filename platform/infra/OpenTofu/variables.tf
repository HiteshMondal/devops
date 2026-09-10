# platform/infra/OpenTofu/variables.tf
# All values here are meant to arrive as TF_VAR_<name> environment
# variables exported by deploy_infra.sh, which in turn reads them from
# .env — .env stays the single source of truth. Defaults below only exist
# as safe fallbacks; they never encode secrets.

variable "gcp_project_id" {
  description = "GCP project ID. Sourced from .env → GCP_PROJECT_ID."
  type        = string

  validation {
    condition     = length(trimspace(var.gcp_project_id)) > 0
    error_message = "gcp_project_id is empty. Set GCP_PROJECT_ID in .env."
  }
}

variable "gcp_region" {
  description = "GCP region. Sourced from .env → GCP_REGION."
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone within gcp_region. Must be us-west1/us-central1/us-east1 to qualify for Always-Free Compute Engine pricing. Sourced from .env → GCP_ZONE."
  type        = string
  default     = "us-central1-a"
}

variable "deploy_target" {
  description = "Deployment stage injected by run.sh (local|prod). Used only for labeling."
  type        = string
  default     = "prod"
}

variable "app_name" {
  description = "Application name. Sourced from .env → APP_NAME."
  type        = string
  default     = "devops-app"
}

variable "app_port" {
  description = "Application container port. Sourced from .env → APP_PORT."
  type        = number
  default     = 8000
}

# GKE

variable "gke_cluster_name" {
  description = "GKE cluster name. Sourced from .env → GKE_CLUSTER_NAME."
  type        = string
  default     = "devops-app-cluster"
}

variable "gke_node_count" {
  description = "Nodes in the GKE node pool. Keep at 1 to stay inside Always-Free compute limits. Sourced from .env → GKE_NODE_COUNT."
  type        = number
  default     = 1
}

variable "gke_machine_type" {
  description = <<-EOT
    GKE node machine type.
    e2-small (2 vCPU / 2GB) is the smallest type that reliably runs GKE's
    own system pods alongside an application pod. e2-micro qualifies for
    Always-Free Compute Engine pricing but is generally too small once
    GKE system daemonsets are scheduled on it — use it only if you accept
    that trade-off. Sourced from .env → GKE_MACHINE_TYPE.
  EOT
  type        = string
  default     = "e2-small"
}

variable "gke_disk_size_gb" {
  description = "Boot disk size per GKE node, GB. 30GB matches the Always-Free persistent-disk allowance. Sourced from .env → GKE_DISK_SIZE_GB."
  type        = number
  default     = 30
}

variable "gke_release_channel" {
  description = "GKE release channel (RAPID|REGULAR|STABLE)."
  type        = string
  default     = "REGULAR"
}

# Cloud SQL — opt-in, NOT covered by GCP Always-Free

variable "enable_cloudsql" {
  description = "Provision Cloud SQL. Cloud SQL has no permanent free tier (unlike GKE/Compute Engine), so this defaults to false — applying this module never bills you for a database unless you explicitly turn it on."
  type        = bool
  default     = false
}

variable "cloudsql_tier" {
  description = "Cloud SQL machine tier. Sourced from .env → CLOUDSQL_TIER."
  type        = string
  default     = "db-f1-micro"
}

variable "cloudsql_disk_size_gb" {
  description = "Cloud SQL disk size, GB. Sourced from .env → CLOUDSQL_DISK_SIZE_GB."
  type        = number
  default     = 10
}

variable "cloudsql_version" {
  description = "Cloud SQL Postgres version. Sourced from .env → CLOUDSQL_VERSION."
  type        = string
  default     = "POSTGRES_15"
}

variable "db_name" {
  description = "Database name. Sourced from .env → DB_NAME."
  type        = string
  default     = "devopsdb"
}

variable "db_username" {
  description = "Database username. Sourced from .env → DB_USERNAME."
  type        = string
  default     = "devops"
}

variable "db_password" {
  description = "Database password. Sourced from .env → DB_PASSWORD. No default on purpose — must arrive via TF_VAR_db_password so it never gets committed."
  type        = string
  sensitive   = true
  default     = ""
}

variable "db_port" {
  description = "Database port. Sourced from .env → DB_PORT."
  type        = number
  default     = 5432
}
