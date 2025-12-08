# ========================================
# Lambda IAM Role - GuardDuty Remediation
# ========================================

resource "aws_iam_role" "guardduty_remediation" {
  name = "security-automation-guardduty-remediation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "guardduty-remediation-role"
    }
  )
}

# IAM policy for GuardDuty remediation Lambda
resource "aws_iam_role_policy" "guardduty_remediation" {
  name = "guardduty-remediation-policy"
  role = aws_iam_role.guardduty_remediation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/security-*"
      },
      {
        Sid    = "IAMUserRemediation"
        Effect = "Allow"
        Action = [
          "iam:GetUser",
          "iam:ListAccessKeys",
          "iam:UpdateAccessKey",
          "iam:DeleteAccessKey",
          "iam:CreateAccessKey",
          "iam:AttachUserPolicy",
          "iam:DetachUserPolicy",
          "iam:PutUserPolicy"
        ]
        Resource = "arn:aws:iam::${local.account_id}:user/*"
      },
      {
        Sid    = "SecretsManagerRotation"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret",
          "secretsmanager:RotateSecret"
        ]
        Resource = "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:*"
      },
      {
        Sid    = "SNSPublish"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.security_notifications.arn
      },
      {
        Sid    = "EC2Isolation"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:CreateSecurityGroup",
          "ec2:ModifyInstanceAttribute",
          "ec2:CreateTags"
        ]
        Resource = "*"
      }
    ]
  })
}

# ========================================
# Lambda IAM Role - S3 Remediation
# ========================================

resource "aws_iam_role" "s3_remediation" {
  name = "security-automation-s3-remediation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "s3-remediation-role"
    }
  )
}

# IAM policy for S3 remediation Lambda
resource "aws_iam_role_policy" "s3_remediation" {
  name = "s3-remediation-policy"
  role = aws_iam_role.s3_remediation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/security-*"
      },
      {
        Sid    = "S3BucketRemediation"
        Effect = "Allow"
        Action = [
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketAcl",
          "s3:PutBucketAcl",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy"
        ]
        Resource = "arn:aws:s3:::*"
      },
      {
        Sid    = "SNSPublish"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.security_notifications.arn
      }
    ]
  })
}

# ========================================
# Lambda IAM Role - Slack Notifier
# ========================================

resource "aws_iam_role" "slack_notifier" {
  name = "security-automation-slack-notifier"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "slack-notifier-role"
    }
  )
}

# IAM policy for Slack notifier Lambda
resource "aws_iam_role_policy" "slack_notifier" {
  name = "slack-notifier-policy"
  role = aws_iam_role.slack_notifier.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/security-*"
      },
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.slack_webhook.arn
      }
    ]
  })
}

# ========================================
# Secrets Manager for Slack Webhook
# ========================================

resource "aws_secretsmanager_secret" "slack_webhook" {
  name                    = "security-automation/slack-webhook"
  description             = "Slack webhook URL for security notifications"
  recovery_window_in_days = 7

  tags = merge(
    local.common_tags,
    {
      Name = "slack-webhook-secret"
    }
  )
}

resource "aws_secretsmanager_secret_version" "slack_webhook" {
  secret_id = aws_secretsmanager_secret.slack_webhook.id
  secret_string = jsonencode({
    webhook_url = var.slack_webhook_url
  })
}

# ========================================
# CloudWatch Log Groups
# ========================================

resource "aws_cloudwatch_log_group" "guardduty_remediation" {
  name              = "/aws/lambda/security-remediation-guardduty"
  retention_in_days = var.log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name = "guardduty-remediation-logs"
    }
  )
}

resource "aws_cloudwatch_log_group" "s3_remediation" {
  name              = "/aws/lambda/security-remediation-s3"
  retention_in_days = var.log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name = "s3-remediation-logs"
    }
  )
}

resource "aws_cloudwatch_log_group" "slack_notifier" {
  name              = "/aws/lambda/security-slack-notifier"
  retention_in_days = var.log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name = "slack-notifier-logs"
    }
  )
}

# ========================================
# Lambda Functions
# ========================================

# Package Lambda function code
data "archive_file" "guardduty_remediation" {
  type        = "zip"
  source_file = "${path.module}/../lambda/guardduty_remediation.py"
  output_path = "${path.module}/lambda_packages/guardduty_remediation.zip"
}

data "archive_file" "s3_remediation" {
  type        = "zip"
  source_file = "${path.module}/../lambda/s3_remediation.py"
  output_path = "${path.module}/lambda_packages/s3_remediation.zip"
}

data "archive_file" "slack_notifier" {
  type        = "zip"
  source_file = "${path.module}/../lambda/slack_notifier.py"
  output_path = "${path.module}/lambda_packages/slack_notifier.zip"
}

# GuardDuty Remediation Lambda
resource "aws_lambda_function" "guardduty_remediation" {
  filename         = data.archive_file.guardduty_remediation.output_path
  function_name    = "security-remediation-guardduty"
  role             = aws_iam_role.guardduty_remediation.arn
  handler          = "guardduty_remediation.lambda_handler"
  source_code_hash = data.archive_file.guardduty_remediation.output_base64sha256
  runtime          = "python3.12"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.security_notifications.arn
      ENVIRONMENT   = var.environment
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.guardduty_remediation
  ]

  tags = merge(
    local.common_tags,
    {
      Name = "guardduty-remediation-lambda"
    }
  )
}

# S3 Remediation Lambda
resource "aws_lambda_function" "s3_remediation" {
  filename         = data.archive_file.s3_remediation.output_path
  function_name    = "security-remediation-s3"
  role             = aws_iam_role.s3_remediation.arn
  handler          = "s3_remediation.lambda_handler"
  source_code_hash = data.archive_file.s3_remediation.output_base64sha256
  runtime          = "python3.12"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.security_notifications.arn
      ENVIRONMENT   = var.environment
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.s3_remediation
  ]

  tags = merge(
    local.common_tags,
    {
      Name = "s3-remediation-lambda"
    }
  )
}

# Slack Notifier Lambda
resource "aws_lambda_function" "slack_notifier" {
  filename         = data.archive_file.slack_notifier.output_path
  function_name    = "security-slack-notifier"
  role             = aws_iam_role.slack_notifier.arn
  handler          = "slack_notifier.lambda_handler"
  source_code_hash = data.archive_file.slack_notifier.output_base64sha256
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      SLACK_WEBHOOK_SECRET_NAME = aws_secretsmanager_secret.slack_webhook.name
      ENVIRONMENT               = var.environment
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.slack_notifier
  ]

  tags = merge(
    local.common_tags,
    {
      Name = "slack-notifier-lambda"
    }
  )
}
