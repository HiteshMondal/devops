###############################################################################
# opentofu_rds.tf — Oracle Autonomous Database (Always Free)
# Always Free: 1 ADB, 20 GB storage, shared ECPU — no time limit
# Region: ap-mumbai-1 (Mumbai)
# Workload Type: Transaction Processing (OLTP) — for app databases
###############################################################################

#------------------------------------------------------------------------------
# Random password for ADB (avoid hardcoding)
#------------------------------------------------------------------------------
resource "random_password" "adb_admin" {
  length           = 24
  special          = true
  override_special = "#$%^&*()-_=+!"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

#------------------------------------------------------------------------------
# OCI Vault — Store ADB credentials securely
# (Vault itself is free; secrets have a small cost — can use env vars instead)
#------------------------------------------------------------------------------
resource "oci_kms_vault" "main" {
  compartment_id = oci_identity_compartment.main.id
  display_name   = "${var.project_name}-${var.environment}-vault"
  vault_type     = "DEFAULT" # Free default vault

  freeform_tags = local.freeform_tags
}

resource "oci_kms_key" "adb" {
  compartment_id = oci_identity_compartment.main.id
  display_name   = "${var.project_name}-${var.environment}-adb-key"
  management_endpoint = oci_kms_vault.main.management_endpoint

  key_shape {
    algorithm = "AES"
    length    = 32 # 256-bit AES
  }

  freeform_tags = local.freeform_tags
}

#------------------------------------------------------------------------------
# Autonomous Database — Always Free
# Workload: OLTP (Transaction Processing)
# Note: APEX workload type is also available for Always Free
#------------------------------------------------------------------------------
resource "oci_database_autonomous_database" "main" {
  compartment_id = oci_identity_compartment.main.id
  display_name   = var.adb_display_name
  db_name        = var.adb_db_name

  # Always Free settings — CRITICAL: is_free_tier must be true
  is_free_tier              = true
  is_auto_scaling_enabled   = false # Not available in free tier
  is_auto_scaling_for_storage_enabled = false

  # Workload — OLTP for general app use
  db_workload = "OLTP"

  # Shared infrastructure (free tier only supports shared)
  db_version = "19c"

  # Compute — not configurable in free tier
  cpu_core_count = 1 # Fixed for free tier

  # Storage — 20 GB free
  data_storage_size_in_tbs = var.adb_storage_tb

  # Credentials
  admin_password = coalesce(var.adb_admin_password, random_password.adb_admin.result)

  # Network access — private endpoint (recommended)
  is_mtls_connection_required = true # mTLS for security
  subnet_id                   = oci_core_subnet.private_db.id
  private_endpoint_label      = "${replace(var.project_name, "-", "")}${var.environment}db"

  # Backup — enabled by default, 60-day retention for Always Free
  is_local_data_guard_enabled = false # Not available in free tier

  # Maintenance — automatic patching
  is_preview_version_with_service_terms_accepted = false

  # Lifecycle
  lifecycle {
    prevent_destroy = true # Safety guard — prevent accidental deletion
    ignore_changes  = [admin_password] # Managed separately after initial creation
  }

  freeform_tags = local.freeform_tags
}

#------------------------------------------------------------------------------
# Download Wallet (mTLS connection) — stored locally for app connectivity
# The wallet is needed for JDBC connections from OKE pods
#------------------------------------------------------------------------------
resource "oci_database_autonomous_database_wallet" "main" {
  autonomous_database_id = oci_database_autonomous_database.main.id
  password               = coalesce(var.adb_admin_password, random_password.adb_admin.result)
  generate_type          = "SINGLE" # Single DB wallet (not all DBs in tenancy)

  base64_encode_content  = true
}

# Save wallet to local file (for uploading to Kubernetes Secret)
resource "local_file" "adb_wallet" {
  content_base64 = oci_database_autonomous_database_wallet.main.content
  filename       = "${path.module}/wallet/adb_wallet.zip"
  file_permission = "0600"
}

#------------------------------------------------------------------------------
# Kubernetes Secret — ADB Wallet & Connection Details
# Apply this to the OKE cluster after provisioning
#------------------------------------------------------------------------------
resource "local_file" "adb_k8s_secret_manifest" {
  content = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "adb-credentials"
      namespace = var.app_namespace
    }
    type = "Opaque"
    stringData = {
      DB_USERNAME        = "ADMIN"
      DB_PASSWORD        = coalesce(var.adb_admin_password, random_password.adb_admin.result)
      DB_CONNECTION_HIGH = "${var.adb_db_name}_high"
      DB_CONNECTION_MED  = "${var.adb_db_name}_medium"
      DB_CONNECTION_LOW  = "${var.adb_db_name}_low"
      DB_HOST            = oci_database_autonomous_database.main.connection_strings[0].host
      DB_PORT            = "1521"
    }
  })

  filename        = "${path.module}/wallet/adb-k8s-secret.yaml"
  file_permission = "0600"
}

#------------------------------------------------------------------------------
# OCI Monitoring Alarms for ADB
#------------------------------------------------------------------------------
data "oci_monitoring_alarm_statuses" "adb" {
  compartment_id = oci_identity_compartment.main.id

  depends_on = [oci_database_autonomous_database.main]
}

resource "oci_monitoring_alarm" "adb_cpu_high" {
  compartment_id        = oci_identity_compartment.main.id
  display_name          = "${var.project_name}-${var.environment}-adb-cpu-alarm"
  is_enabled            = true
  metric_compartment_id = oci_identity_compartment.main.id

  query     = "CpuUtilization[5m].mean() > 80"
  namespace = "oci_autonomous_database"

  severity           = "WARNING"
  pending_duration   = "PT5M"
  message_format     = "ONS_OPTIMIZED"
  is_notifications_per_metric_dimension_enabled = false

  destinations   = []
  rule_name      = "adb-cpu-high"

  freeform_tags = local.freeform_tags
}

resource "oci_monitoring_alarm" "adb_storage_high" {
  compartment_id        = oci_identity_compartment.main.id
  display_name          = "${var.project_name}-${var.environment}-adb-storage-alarm"
  is_enabled            = true
  metric_compartment_id = oci_identity_compartment.main.id

  query     = "StorageUtilization[5m].mean() > 80"
  namespace = "oci_autonomous_database"

  severity         = "CRITICAL"
  pending_duration = "PT5M"
  message_format   = "ONS_OPTIMIZED"
  is_notifications_per_metric_dimension_enabled = false

  destinations = []
  rule_name    = "adb-storage-high"

  freeform_tags = local.freeform_tags
}
