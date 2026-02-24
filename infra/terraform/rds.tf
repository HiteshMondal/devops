###############################################################################
# rds.tf — RDS PostgreSQL (Free Tier)
# AWS Free Tier: db.t3.micro, 20 GB, Single-AZ, no Multi-AZ
# Region: ap-south-1 (Mumbai)
###############################################################################

#------------------------------------------------------------------------------
# DB Subnet Group (RDS in private subnets)
#------------------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-db-subnet-group"
  description = "RDS subnet group — private subnets only"
  subnet_ids  = aws_subnet.private[*].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  })
}

#------------------------------------------------------------------------------
# RDS Parameter Group — PostgreSQL optimised settings
#------------------------------------------------------------------------------
resource "aws_db_parameter_group" "main" {
  name        = "${var.project_name}-${var.environment}-pg16"
  family      = "postgres16"
  description = "Custom PostgreSQL 16 parameters for ${var.project_name}"

  # Connection pooling and performance settings
  parameter {
    name  = "max_connections"
    value = "100" # Appropriate for db.t3.micro (1 GB RAM)
  }

  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/4096}"
  }

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
    value = "0"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # Log queries slower than 1 second
  }

  parameter {
    name  = "log_statement"
    value = "ddl" # Log DDL statements only
  }

  parameter {
    name  = "rds.force_ssl"
    value = "1" # Enforce SSL connections
  }

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Random Password for RDS (recommended over plain-text variables)
#------------------------------------------------------------------------------
resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+"
}

#------------------------------------------------------------------------------
# AWS Secrets Manager — Store DB credentials securely
#------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}/${var.environment}/db-credentials"
  description             = "RDS PostgreSQL credentials for ${var.project_name} ${var.environment}"
  recovery_window_in_days = 7

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = aws_db_instance.main.db_name
    url      = "postgresql://${var.db_username}:${random_password.db.result}@${aws_db_instance.main.address}:${aws_db_instance.main.port}/${aws_db_instance.main.db_name}"
  })
}

#------------------------------------------------------------------------------
# RDS Instance — PostgreSQL 16 (Free Tier)
#------------------------------------------------------------------------------
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-postgres"

  # Engine
  engine               = "postgres"
  engine_version       = var.db_engine_version
  instance_class       = var.db_instance_class # db.t3.micro = free tier
  parameter_group_name = aws_db_parameter_group.main.name

  # Storage — 20 GB = free tier limit
  allocated_storage     = var.db_storage_gb
  max_allocated_storage = 100 # Auto-scaling up to 100 GB
  storage_type          = "gp2"
  storage_encrypted     = true

  # Credentials
  db_name  = local.db_name
  username = var.db_username
  password = random_password.db.result

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false # Never expose RDS publicly

  # Availability
  multi_az               = var.db_multi_az         # false for free tier
  availability_zone      = var.availability_zones[0] # Single AZ when multi_az = false

  # Backup — free tier includes automated backups
  backup_retention_period = var.db_backup_retention_days
  backup_window           = "02:00-03:00"   # UTC — 7:30 AM IST
  maintenance_window      = "Mon:03:00-Mon:04:00" # UTC — after backup window

  # Performance Insights — free for 7 days retention on db.t3.micro
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  # Enhanced monitoring — basic, free tier compatible
  monitoring_interval = 0 # Set to 60 for enhanced monitoring (requires IAM role)

  # Deletion protection — ALWAYS enable in production
  deletion_protection = true

  # Skip final snapshot — set false for production!
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-${var.environment}-final-snapshot"
  copy_tags_to_snapshot     = true

  # Auto minor version upgrades
  auto_minor_version_upgrade = true
  apply_immediately          = false # Apply changes during maintenance window

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-postgres"
  })

  lifecycle {
    ignore_changes = [password] # Managed by Secrets Manager rotation
  }
}

#------------------------------------------------------------------------------
# CloudWatch Alarms for RDS
#------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "RDS CPU utilisation exceeded 80%"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "2000000000" # 2 GB
  alarm_description   = "RDS free storage below 2 GB"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "RDS connections exceeded 80"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = local.common_tags
}