# ========================================
# SNS Topic for Security Notifications
# ========================================

resource "aws_sns_topic" "security_notifications" {
  name              = "security-automation-notifications"
  display_name      = "Security Automation Alerts"
  kms_master_key_id = aws_kms_key.sns.id

  tags = merge(
    local.common_tags,
    {
      Name = "security-notifications"
    }
  )
}

# Email subscription
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.security_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Lambda subscription for Slack notifications
resource "aws_sns_topic_subscription" "slack_lambda" {
  topic_arn = aws_sns_topic.security_notifications.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_notifier.arn
}

# ========================================
# SNS Topic Policy
# ========================================

resource "aws_sns_topic_policy" "security_notifications" {
  arn = aws_sns_topic.security_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchEventsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.security_notifications.arn
      },
      {
        Sid    = "AllowLambdaToPublish"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.security_notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# ========================================
# KMS Key for SNS Encryption
# ========================================

resource "aws_kms_key" "sns" {
  description             = "KMS key for SNS topic encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(
    local.common_tags,
    {
      Name = "sns-encryption-key"
    }
  )
}

resource "aws_kms_alias" "sns" {
  name          = "alias/security-notifications"
  target_key_id = aws_kms_key.sns.key_id
}

resource "aws_kms_key_policy" "sns" {
  key_id = aws_kms_key.sns.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM policies"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow SNS to use the key"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      },
      {
        Sid    = "Allow CloudWatch Events to use the key"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
}

# ========================================
# Dead Letter Queue (DLQ) for Failed Notifications
# ========================================

resource "aws_sqs_queue" "dlq" {
  count = var.enable_dlq ? 1 : 0

  name                      = "security-automation-dlq"
  message_retention_seconds = 1209600 # 14 days

  kms_master_key_id                 = aws_kms_key.sns.id
  kms_data_key_reuse_period_seconds = 300

  tags = merge(
    local.common_tags,
    {
      Name = "security-automation-dlq"
    }
  )
}

resource "aws_sqs_queue_policy" "dlq" {
  count = var.enable_dlq ? 1 : 0

  queue_url = aws_sqs_queue.dlq[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSNSToSendMessages"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.dlq[0].arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.security_notifications.arn
          }
        }
      }
    ]
  })
}
