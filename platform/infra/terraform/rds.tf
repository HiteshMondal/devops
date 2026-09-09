########################################
# platform/infra/terraform/rds.tf
#
# Standalone database instance. The app only needs DB_HOST/DB_PORT/etc
# at runtime (injected via Kubernetes ConfigMap/Secret by
# platform/deployment/kubernetes), so nothing here references app code
# or Kubernetes manifests, and nothing there needs to reference this file.
########################################

resource "aws_db_subnet_group" "this" {
  name = "${var.app_name}-db-subnets"
  # Always private, regardless of the NAT-gateway/public-node choice above —
  # the database itself is never internet-facing.
  subnet_ids = module.vpc.private_subnets

  tags = local.common_tags
}

resource "aws_security_group" "rds" {
  name        = "${var.app_name}-rds-sg"
  description = "Allow database access only from the EKS worker nodes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Database access from EKS worker nodes"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_db_instance" "this" {
  identifier = "${var.app_name}-db"

  engine         = var.db_engine
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage # disable storage autoscaling to avoid surprise Free Tier overage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = var.db_port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  multi_az                  = var.db_multi_az
  backup_retention_period   = var.db_backup_retention_days
  deletion_protection       = var.db_deletion_protection
  skip_final_snapshot       = var.db_skip_final_snapshot
  final_snapshot_identifier = var.db_skip_final_snapshot ? null : "${var.app_name}-db-final-${var.environment}"

  auto_minor_version_upgrade = true
  apply_immediately          = true

  tags = local.common_tags
}
