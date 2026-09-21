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

# No topic policy. The Lambda publishes (including as its dead-letter target)
# with its execution role, which the owning account already trusts. A statement
# for the bare lambda.amazonaws.com service principal without an aws:SourceAccount
# condition would let the Lambda service publish on behalf of ANY account.

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
  name = "${local.name_prefix}-remediation-lambda-role"
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

# No AWSLambdaBasicExecutionRole: it grants logs actions on every log group.
# The scoped WriteOwnLogs statement below replaces it.

# Remediation permissions policy
resource "aws_iam_role_policy" "remediation_permissions" {
  name = "${local.name_prefix}-remediation-permissions"
  role = aws_iam_role.remediation_lambda.id

  # Least privilege: exactly the API calls lambda/remediate_credentials/main.py makes.
  # No role, group, or managed-policy actions, so the function cannot grant itself
  # more access (the old role/* AttachRolePolicy grant was a self-escalation path).
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Deactivate keys, write the inline deny-all quarantine policy, remove console password.
        Sid    = "ContainCompromisedUser"
        Effect = "Allow"
        Action = [
          "iam:ListAccessKeys",
          "iam:UpdateAccessKey",
          "iam:PutUserPolicy",
          "iam:DeleteLoginProfile"
        ]
        Resource = "arn:aws:iam::${local.account_id}:user/*"
      },
      {
        # Must match the path the code writes: f"{PROJECT_NAME}/incidents/{user}/{finding_id}".
        # The previous prefix (name_prefix/*) never matched, so records silently failed.
        Sid      = "RecordIncident"
        Effect   = "Allow"
        Action   = ["secretsmanager:CreateSecret"]
        Resource = "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${var.project_name}/incidents/*"
      },
      {
        # Notifications, and the topic doubles as the async dead-letter target.
        Sid      = "NotifyAndDeadLetter"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.security_alerts.arn
      },
      {
        # Only this function's own log group, which Terraform creates up front.
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.remediation_lambda.arn}:*"
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
      SNS_TOPIC_ARN       = aws_sns_topic.security_alerts.arn
      SLACK_WEBHOOK_URL   = var.slack_webhook_url
      AUTO_REMEDIATE_HIGH = var.auto_remediate_high_severity
      ENVIRONMENT         = var.environment
      PROJECT_NAME        = var.project_name
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
    maximum_event_age_in_seconds = 3600 # 1 hour
    maximum_retry_attempts       = 2
  }

  dead_letter_config {
    arn = aws_sns_topic.security_alerts.arn
  }
}
