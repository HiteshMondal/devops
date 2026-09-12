########################################
# platform/infra/terraform/self_healing.tf
#
# Self-Healing Infrastructure: CloudWatch Alarms -> SNS -> Lambda that
# remediates unhealthy EKS worker nodes and RDS. The Lambda source lives
# in ./lambda/self_healing.py and is zipped automatically by the
# archive_file data source below — `terraform apply` alone packages and
# deploys it, no separate build/zip step or CI job needed.
#
# Entirely opt-in (var.enable_self_healing) and additive.
########################################

data "archive_file" "self_healing_lambda" {
  count       = var.enable_self_healing ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/self_healing.py"
  output_path = "${path.module}/.build/self_healing.zip"
}

resource "aws_iam_role" "self_healing_lambda" {
  count = var.enable_self_healing ? 1 : 0
  name  = "${var.app_name}-self-healing-lambda"

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

resource "aws_iam_role_policy" "self_healing_lambda" {
  count = var.enable_self_healing ? 1 : 0
  name  = "${var.app_name}-self-healing-lambda-policy"
  role  = aws_iam_role.self_healing_lambda[0].id

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
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["rds:RebootDBInstance", "rds:DescribeDBInstances"]
        Resource = aws_db_instance.this.arn
      }
    ]
  })
}

resource "aws_lambda_function" "self_healing" {
  count            = var.enable_self_healing ? 1 : 0
  function_name    = "${var.app_name}-self-healing"
  role             = aws_iam_role.self_healing_lambda[0].arn
  handler          = "self_healing.handler"
  runtime          = "python3.12"
  timeout          = 60
  filename         = data.archive_file.self_healing_lambda[0].output_path
  source_code_hash = data.archive_file.self_healing_lambda[0].output_base64sha256

  environment {
    variables = {
      ASG_NAME                = module.eks.eks_managed_node_groups["default"].node_group_autoscaling_group_names[0]
      DB_INSTANCE_IDENTIFIER  = aws_db_instance.this.id
    }
  }

  tags = local.common_tags
}

resource "aws_sns_topic" "self_healing" {
  count = var.enable_self_healing ? 1 : 0
  name  = "${var.app_name}-self-healing-alarms"
  tags  = local.common_tags
}

resource "aws_sns_topic_subscription" "self_healing_lambda" {
  count     = var.enable_self_healing ? 1 : 0
  topic_arn = aws_sns_topic.self_healing[0].arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.self_healing[0].arn
}

resource "aws_lambda_permission" "sns_invoke_self_healing" {
  count         = var.enable_self_healing ? 1 : 0
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.self_healing[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.self_healing[0].arn
}

# Alarm: EKS worker node ASG has an unhealthy instance count > 0
resource "aws_cloudwatch_metric_alarm" "asg_unhealthy_nodes" {
  count               = var.enable_self_healing ? 1 : 0
  alarm_name          = "${var.app_name}-asg-node-unhealthy"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = 300
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Fires when the EKS worker ASG reports fewer in-service instances than desired; triggers node replacement."
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = module.eks.eks_managed_node_groups["default"].node_group_autoscaling_group_names[0]
  }

  alarm_actions = [aws_sns_topic.self_healing[0].arn]

  # NOTE: GroupInServiceInstances alone isn't a perfect unhealthy-node
  # signal; teams needing tighter detection commonly pair this with an
  # ASG "EC2 status check failed" alarm on StatusCheckFailed_Instance.
}

resource "aws_cloudwatch_metric_alarm" "rds_status_check" {
  count               = var.enable_self_healing ? 1 : 0
  alarm_name          = "${var.app_name}-rds-status-check-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Fires when RDS fails status checks; triggers an automated reboot."
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.id
  }

  alarm_actions = [aws_sns_topic.self_healing[0].arn]
}
