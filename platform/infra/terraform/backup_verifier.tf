data "archive_file" "backup_verifier" {
  count       = var.enable_cloud_storage ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/backup_verifier.py"
  output_path = "${path.module}/.build/backup_verifier.zip"
}

resource "aws_iam_role" "backup_verifier" {
  count = var.enable_cloud_storage ? 1 : 0
  name  = "${var.app_name}-backup-verifier"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "backup_verifier" {
  count = var.enable_cloud_storage ? 1 : 0
  name  = "${var.app_name}-backup-verifier-policy"
  role  = aws_iam_role.backup_verifier[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "arn:aws:logs:*:*:*" },
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.files_primary[0].arn}/postgres/*" },
      { Effect = "Allow", Action = ["cloudwatch:PutMetricData"], Resource = "*",
        Condition = { StringEquals = { "cloudwatch:namespace" = "DevopsApp/Backups" } } }
    ]
  })
}

resource "aws_lambda_function" "backup_verifier" {
  count            = var.enable_cloud_storage ? 1 : 0
  function_name    = "${var.app_name}-backup-verifier"
  role             = aws_iam_role.backup_verifier[0].arn
  handler          = "backup_verifier.handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.backup_verifier[0].output_path
  source_code_hash = data.archive_file.backup_verifier[0].output_base64sha256
  environment { variables = { METRIC_NAMESPACE = "DevopsApp/Backups" } }
  tags = local.common_tags
}

resource "aws_lambda_permission" "s3_invoke_backup_verifier" {
  count          = var.enable_cloud_storage ? 1 : 0
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.backup_verifier[0].function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.files_primary[0].arn
  source_account = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket_notification" "backup_uploaded" {
  count  = var.enable_cloud_storage ? 1 : 0
  bucket = aws_s3_bucket.files_primary[0].id
  lambda_function {
    lambda_function_arn = aws_lambda_function.backup_verifier[0].arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "postgres/"
    filter_suffix       = ".sql.gz"
  }
  depends_on = [aws_lambda_permission.s3_invoke_backup_verifier]
}
