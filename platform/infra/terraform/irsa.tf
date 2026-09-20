########################################
# platform/infra/terraform/irsa.tf
#
# IAM role for the postgres-backup CronJob (IRSA). Only created when the
# backup bucket exists (var.enable_cloud_storage).
########################################

data "aws_iam_policy_document" "postgres_backup_assume" {
  count = var.enable_cloud_storage ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:devops-app:postgres-backup-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "postgres_backup" {
  count              = var.enable_cloud_storage ? 1 : 0
  name               = "${var.app_name}-postgres-backup"
  assume_role_policy = data.aws_iam_policy_document.postgres_backup_assume[0].json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "postgres_backup" {
  count = var.enable_cloud_storage ? 1 : 0
  name  = "${var.app_name}-postgres-backup-policy"
  role  = aws_iam_role.postgres_backup[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.files_primary[0].arn}/postgres/*"
      }
    ]
  })
}
