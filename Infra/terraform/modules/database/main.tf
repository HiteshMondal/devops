# terraform/modules/database/main.tf
# RDS PostgreSQL with Multi-AZ and automated backups

# DB Subnet Group is created in VPC module

# RDS Parameter Group
resource "aws_db_parameter_group" "main" {
  name   = "${var.project_name}-${var.environment}-pg"
  family = "postgres15"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_duration"
    value = "1"
  }

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-pg"
    }
  )
}

# Random password for DB
resource "random_password" "db_password" {
  length  = 32
  special = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Store password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name        = "${var.project_name}-${var.environment}-db-password"
  description = "RDS PostgreSQL password for ${var.project_name}-${var.environment}"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    engine   = "postgres"
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = var.db_name
  })
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-${var.environment}-db"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result
  port     = 5432

  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [var.db_security_group_id]
  parameter_group_name   = aws_db_parameter_group.main.name

  multi_az               = var.multi_az
  availability_zone      = var.multi_az ? null : var.availability_zones[0]
  publicly_accessible    = false

  # Backup configuration
  backup_retention_period = var.backup_retention_period
  backup_window          = var.backup_window
  maintenance_window     = var.maintenance_window

  # Performance Insights
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  performance_insights_enabled    = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? 7 : null

  # Monitoring
  monitoring_interval = var.enhanced_monitoring_enabled ? 60 : 0
  monitoring_role_arn = var.enhanced_monitoring_enabled ? aws_iam_role.rds_monitoring[0].arn : null

  # Delete protection
  deletion_protection = var.deletion_protection
  skip_final_snapshot = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project_name}-${var.environment}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # Auto minor version upgrade
  auto_minor_version_upgrade = true

  # Copy tags to snapshots
  copy_tags_to_snapshot = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-db"
    }
  )

  lifecycle {
    ignore_changes = [
      final_snapshot_identifier
    ]
  }
}

# IAM Role for Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  count = var.enhanced_monitoring_enabled ? 1 : 0
  name  = "${var.project_name}-${var.environment}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count      = var.enhanced_monitoring_enabled ? 1 : 0
  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# CloudWatch Alarms for RDS
resource "aws_cloudwatch_metric_alarm" "db_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-db-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS CPU utilization"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "db_storage" {
  alarm_name          = "${var.project_name}-${var.environment}-db-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "10000000000" # 10GB in bytes
  alarm_description   = "This metric monitors RDS free storage space"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "db_memory" {
  alarm_name          = "${var.project_name}-${var.environment}-db-low-memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = "120"
  statistic           = "Average"
  threshold           = "1000000000" # 1GB in bytes
  alarm_description   = "This metric monitors RDS freeable memory"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "db_connections" {
  alarm_name          = "${var.project_name}-${var.environment}-db-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS database connections"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = var.tags
}

# Read Replica (optional, for production)
resource "aws_db_instance" "replica" {
  count              = var.create_read_replica ? 1 : 0
  identifier         = "${var.project_name}-${var.environment}-db-replica"
  replicate_source_db = aws_db_instance.main.identifier
  instance_class     = var.db_instance_class

  publicly_accessible = false
  skip_final_snapshot = true

  # Performance Insights
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? 7 : null

  # Monitoring
  monitoring_interval = var.enhanced_monitoring_enabled ? 60 : 0
  monitoring_role_arn = var.enhanced_monitoring_enabled ? aws_iam_role.rds_monitoring[0].arn : null

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-db-replica"
    }
  )
}