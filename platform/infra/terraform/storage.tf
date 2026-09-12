########################################
# platform/infra/terraform/storage.tf
#
# Distributed Cloud File System: an S3 bucket in var.aws_region, versioned
# and replicated to a second bucket in var.cloud_storage_replica_region.
# Entirely opt-in (var.enable_cloud_storage) and additive — no other file
# in this directory references these resources, so leaving the flag off
# has zero effect on the rest of the stack.
########################################

# Primary bucket (var.aws_region)

resource "aws_s3_bucket" "files_primary" {
  count  = var.enable_cloud_storage ? 1 : 0
  bucket = "${var.app_name}-files-${var.aws_region}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "files_primary" {
  count  = var.enable_cloud_storage ? 1 : 0
  bucket = aws_s3_bucket.files_primary[0].id
  versioning_configuration {
    status = "Enabled" # required for CRR
  }
}

resource "aws_s3_bucket_public_access_block" "files_primary" {
  count                   = var.enable_cloud_storage ? 1 : 0
  bucket                  = aws_s3_bucket.files_primary[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "files_primary" {
  count  = var.enable_cloud_storage ? 1 : 0
  bucket = aws_s3_bucket.files_primary[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Replica bucket (var.cloud_storage_replica_region) — needs its own
# provider alias since the default provider is pinned to var.aws_region.

provider "aws" {
  alias  = "replica"
  region = var.cloud_storage_replica_region

  default_tags {
    tags = local.common_tags
  }
}

resource "aws_s3_bucket" "files_replica" {
  count    = var.enable_cloud_storage ? 1 : 0
  provider = aws.replica
  bucket   = "${var.app_name}-files-${var.cloud_storage_replica_region}"
  tags     = local.common_tags
}

resource "aws_s3_bucket_versioning" "files_replica" {
  count    = var.enable_cloud_storage ? 1 : 0
  provider = aws.replica
  bucket   = aws_s3_bucket.files_replica[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "files_replica" {
  count                   = var.enable_cloud_storage ? 1 : 0
  provider                = aws.replica
  bucket                  = aws_s3_bucket.files_replica[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM role S3 assumes to perform replication

resource "aws_iam_role" "s3_replication" {
  count = var.enable_cloud_storage ? 1 : 0
  name  = "${var.app_name}-s3-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "s3_replication" {
  count = var.enable_cloud_storage ? 1 : 0
  name  = "${var.app_name}-s3-replication-policy"
  role  = aws_iam_role.s3_replication[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
        Resource = aws_s3_bucket.files_primary[0].arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"]
        Resource = "${aws_s3_bucket.files_primary[0].arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
        Resource = "${aws_s3_bucket.files_replica[0].arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "files" {
  count      = var.enable_cloud_storage ? 1 : 0
  depends_on = [aws_s3_bucket_versioning.files_primary, aws_s3_bucket_versioning.files_replica]

  bucket = aws_s3_bucket.files_primary[0].id
  role   = aws_iam_role.s3_replication[0].arn

  rule {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.files_replica[0].arn
      storage_class = "STANDARD"
    }
  }
}

output "cloud_storage_primary_bucket" {
  description = "Primary distributed-filesystem bucket (null when disabled)."
  value       = var.enable_cloud_storage ? aws_s3_bucket.files_primary[0].bucket : null
}

output "cloud_storage_replica_bucket" {
  description = "Cross-region replica bucket (null when disabled)."
  value       = var.enable_cloud_storage ? aws_s3_bucket.files_replica[0].bucket : null
}
