########################################
# platform/infra/terraform/dr.tf
#
# Multi-Cloud (same-cloud, cross-region) Disaster Recovery: a scheduled
# Lambda snapshots RDS and copies the snapshot into
# var.cloud_storage_replica_region, so a new RDS instance can be restored
# there if the primary region is unavailable. Lambda source lives in
# ./lambda/dr_snapshot_copy.py and is zipped automatically via
# archive_file — `terraform apply` alone packages and deploys it.
#
# Entirely opt-in (var.enable_dr_backup) and additive.
########################################

data "archive_file" "dr_snapshot_lambda" {
  count       = var.enable_dr_backup ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/dr_snapshot_copy.py"
  output_path = "${path.module}/.build/dr_snapshot_copy.zip"
}

resource "aws_iam_role" "dr_snapshot_lambda" {
  count = var.enable_dr_backup ? 1 : 0
  name  = "${var.app_name}-dr-snapshot-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "dr_snapshot_lambda" {
  count = var.enable_dr_backup ? 1 : 0
  name  = "${var.app_name}-dr-snapshot-lambda-policy"
  role  = aws_iam_role.dr_snapshot_lambda[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:CreateDBSnapshot",
          "rds:DescribeDBSnapshots",
          "rds:CopyDBSnapshot",
          "rds:DeleteDBSnapshot",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "dr_snapshot" {
  count            = var.enable_dr_backup ? 1 : 0
  function_name    = "${var.app_name}-dr-snapshot-copy"
  role             = aws_iam_role.dr_snapshot_lambda[0].arn
  handler          = "dr_snapshot_copy.handler"
  runtime          = "python3.12"
  timeout          = 300 # snapshot creation + waiter can take a few minutes
  filename         = data.archive_file.dr_snapshot_lambda[0].output_path
  source_code_hash = data.archive_file.dr_snapshot_lambda[0].output_base64sha256

  environment {
    variables = {
      DB_INSTANCE_IDENTIFIER = aws_db_instance.this.id
      DR_REGION              = var.cloud_storage_replica_region
      DR_RETENTION_DAYS      = tostring(var.dr_snapshot_retention_days)
    }
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_event_rule" "dr_snapshot_schedule" {
  count               = var.enable_dr_backup ? 1 : 0
  name                = "${var.app_name}-dr-snapshot-schedule"
  schedule_expression = var.dr_backup_schedule_expression
  tags                = local.common_tags
}

resource "aws_cloudwatch_event_target" "dr_snapshot_schedule" {
  count     = var.enable_dr_backup ? 1 : 0
  rule      = aws_cloudwatch_event_rule.dr_snapshot_schedule[0].name
  target_id = "dr-snapshot-lambda"
  arn       = aws_lambda_function.dr_snapshot[0].arn
}

resource "aws_lambda_permission" "eventbridge_invoke_dr_snapshot" {
  count         = var.enable_dr_backup ? 1 : 0
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dr_snapshot[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.dr_snapshot_schedule[0].arn
}

output "dr_snapshot_lambda_name" {
  description = "Name of the DR snapshot Lambda (null when disabled)."
  value       = var.enable_dr_backup ? aws_lambda_function.dr_snapshot[0].function_name : null
}
