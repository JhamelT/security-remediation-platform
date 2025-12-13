terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Optional: Uncomment for remote state
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "security-remediation/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name

  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(
    var.tags,
    {
      Environment = var.environment
    }
  )
}

# ============================================================================
# GUARDDUTY DETECTOR
# ============================================================================

resource "aws_guardduty_detector" "main" {
  count = var.enable_guardduty ? 1 : 0

  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = false # Enable if using EKS
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = false # Enable for EC2 workloads
        }
      }
    }
  }

  tags = {
    Name = "${local.name_prefix}-detector"
  }
}

# ============================================================================
# SNS TOPIC FOR NOTIFICATIONS
# ============================================================================

resource "aws_sns_topic" "security_alerts" {
  name              = "${local.name_prefix}-security-alerts"
  display_name      = "Security Remediation Alerts"
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name = "${local.name_prefix}-security-alerts"
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_sns_topic_policy" "security_alerts" {
  arn = aws_sns_topic.security_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.security_alerts.arn
      }
    ]
  })
}

# ============================================================================
# CLOUDWATCH LOG GROUP FOR LAMBDA
# ============================================================================

resource "aws_cloudwatch_log_group" "remediation_lambda" {
  name              = "/aws/lambda/${local.name_prefix}-credential-remediation"
  retention_in_days = var.lambda_log_retention_days
  kms_key_id        = null # Use default encryption for cost savings

  tags = {
    Name = "${local.name_prefix}-credential-remediation-logs"
  }
}

# ============================================================================
# IAM ROLE FOR LAMBDA REMEDIATION FUNCTION
# ============================================================================

resource "aws_iam_role" "remediation_lambda" {
  name               = "${local.name_prefix}-remediation-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-remediation-lambda-role"
  }
}

# Lambda basic execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.remediation_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Remediation permissions policy
resource "aws_iam_role_policy" "remediation_permissions" {
  name = "${local.name_prefix}-remediation-permissions"
  role = aws_iam_role.remediation_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "IAMUserManagement"
        Effect = "Allow"
        Action = [
          "iam:GetUser",
          "iam:ListAccessKeys",
          "iam:DeleteAccessKey",
          "iam:DeactivateAccessKey",
          "iam:UpdateAccessKey",
          "iam:CreateAccessKey",
          "iam:ListAttachedUserPolicies",
          "iam:ListUserPolicies",
          "iam:AttachUserPolicy",
          "iam:DetachUserPolicy",
          "iam:PutUserPolicy",
          "iam:DeleteUserPolicy",
          "iam:GetUserPolicy",
          "iam:ListGroupsForUser",
          "iam:RemoveUserFromGroup",
          "iam:CreateLoginProfile",
          "iam:DeleteLoginProfile",
          "iam:GetLoginProfile"
        ]
        Resource = "arn:aws:iam::${local.account_id}:user/*"
      },
      {
        Sid    = "IAMRoleManagement"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies"
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/*"
      },
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:UpdateSecret",
          "secretsmanager:PutSecretValue",
          "secretsmanager:RotateSecret",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${local.name_prefix}/*"
      },
      {
        Sid    = "SNSPublish"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.security_alerts.arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${local.name_prefix}-*"
      },
      {
        Sid    = "GuardDutyRead"
        Effect = "Allow"
        Action = [
          "guardduty:GetFindings",
          "guardduty:ListFindings"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# LAMBDA FUNCTION - CREDENTIAL REMEDIATION
# ============================================================================

# Package Lambda function code
data "archive_file" "remediation_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/./lambda/remediate_credentials"
  output_path = "${path.module}/.terraform/archive/remediate_credentials.zip"
}

resource "aws_lambda_function" "credential_remediation" {
  filename         = data.archive_file.remediation_lambda.output_path
  function_name    = "${local.name_prefix}-credential-remediation"
  role             = aws_iam_role.remediation_lambda.arn
  handler          = "main.lambda_handler"
  source_code_hash = data.archive_file.remediation_lambda.output_base64sha256
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      SNS_TOPIC_ARN           = aws_sns_topic.security_alerts.arn
      SLACK_WEBHOOK_URL       = var.slack_webhook_url
      AUTO_REMEDIATE_HIGH     = var.auto_remediate_high_severity
      ENVIRONMENT             = var.environment
      PROJECT_NAME            = var.project_name
    }
  }

  tracing_config {
    mode = "Active" # Enable X-Ray for distributed tracing
  }

  tags = {
    Name = "${local.name_prefix}-credential-remediation"
  }

  depends_on = [
    aws_cloudwatch_log_group.remediation_lambda
  ]
}

# Allow EventBridge to invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.credential_remediation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_findings.arn
}

# ============================================================================
# EVENTBRIDGE RULE - GUARDDUTY FINDINGS
# ============================================================================

resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "${local.name_prefix}-guardduty-findings"
  description = "Capture GuardDuty findings for automated remediation"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [
        { numeric = [">", 3.9] } # Medium to Critical (4.0 - 8.9+)
      ]
    }
  })

  tags = {
    Name = "${local.name_prefix}-guardduty-findings"
  }
}

resource "aws_cloudwatch_event_target" "remediation_lambda" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "RemediationLambda"
  arn       = aws_lambda_function.credential_remediation.arn

  retry_policy {
    maximum_event_age_in_seconds = 3600  # 1 hour
    maximum_retry_attempts  = 2
  }

  dead_letter_config {
    arn = aws_sns_topic.security_alerts.arn
  }
}
