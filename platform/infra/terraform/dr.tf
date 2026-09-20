########################################
# platform/infra/terraform/dr.tf
#
# Cross-region disaster recovery using RDS's native automated-backup
# replication. No Lambda, no timeouts, retention handled by RDS.
# Opt-in via var.enable_dr_backup.
########################################

resource "aws_kms_key" "rds_dr" {
  count                   = var.enable_dr_backup ? 1 : 0
  provider                = aws.replica
  description             = "CMK for ${var.app_name} RDS DR-region backups"
  deletion_window_in_days = 7
  tags                    = local.common_tags
}

resource "aws_db_instance_automated_backups_replication" "dr" {
  count                  = var.enable_dr_backup ? 1 : 0
  provider               = aws.replica
  source_db_instance_arn = aws_db_instance.this.arn
  kms_key_id             = aws_kms_key.rds_dr[0].arn
  retention_period       = var.dr_snapshot_retention_days
}

output "dr_replicated_backups_region" {
  description = "Region holding replicated RDS automated backups (null when disabled)."
  value       = var.enable_dr_backup ? var.cloud_storage_replica_region : null
}
