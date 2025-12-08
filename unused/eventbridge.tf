# ========================================
# EventBridge Rules for GuardDuty Findings
# ========================================

# Rule for CRITICAL severity GuardDuty findings
resource "aws_cloudwatch_event_rule" "guardduty_critical" {
  name        = "security-automation-guardduty-critical"
  description = "Capture critical GuardDuty findings for immediate remediation"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [
        { numeric = [">=", 7.0] } # CRITICAL (7.0-8.9) and HIGH (4.0-6.9)
      ]
      type = [
        "UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.InsideAWS",
        "UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS",
        "CredentialAccess:IAMUser/AnomalousBehavior",
        "Stealth:IAMUser/CloudTrailLoggingDisabled",
        "Policy:IAMUser/RootCredentialUsage"
      ]
    }
  })

  tags = merge(
    local.common_tags,
    {
      Name     = "guardduty-critical-rule"
      Severity = "critical"
    }
  )
}

# Target: Lambda function for critical findings
resource "aws_cloudwatch_event_target" "guardduty_critical_lambda" {
  rule      = aws_cloudwatch_event_rule.guardduty_critical.name
  target_id = "GuardDutyRemediationLambda"
  arn       = aws_lambda_function.guardduty_remediation.arn

  retry_policy {
    maximum_retry_attempts = 2
    maximum_event_age      = 3600 # 1 hour
  }

  dead_letter_config {
    arn = var.enable_dlq ? aws_sqs_queue.dlq[0].arn : null
  }
}

# Target: SNS notification for critical findings
resource "aws_cloudwatch_event_target" "guardduty_critical_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_critical.name
  target_id = "SecurityNotificationsTopic"
  arn       = aws_sns_topic.security_notifications.arn

  input_transformer {
    input_paths = {
      severity    = "$.detail.severity"
      type        = "$.detail.type"
      description = "$.detail.description"
      accountId   = "$.detail.accountId"
      region      = "$.detail.region"
      time        = "$.detail.updatedAt"
    }

    input_template = <<EOF
{
  "alert_type": "GuardDuty CRITICAL Finding",
  "severity": <severity>,
  "finding_type": <type>,
  "description": <description>,
  "account_id": <accountId>,
  "region": <region>,
  "timestamp": <time>,
  "action": "Automated remediation triggered"
}
EOF
  }
}

# Rule for HIGH severity GuardDuty findings
resource "aws_cloudwatch_event_rule" "guardduty_high" {
  name        = "security-automation-guardduty-high"
  description = "Capture high severity GuardDuty findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [
        { numeric = [">=", 4.0, "<", 7.0] } # HIGH severity (4.0-6.9)
      ]
    }
  })

  tags = merge(
    local.common_tags,
    {
      Name     = "guardduty-high-rule"
      Severity = "high"
    }
  )
}

# Target: Lambda function for high severity findings
resource "aws_cloudwatch_event_target" "guardduty_high_lambda" {
  rule      = aws_cloudwatch_event_rule.guardduty_high.name
  target_id = "GuardDutyRemediationLambda"
  arn       = aws_lambda_function.guardduty_remediation.arn

  retry_policy {
    maximum_retry_attempts = 2
    maximum_event_age      = 3600
  }

  dead_letter_config {
    arn = var.enable_dlq ? aws_sqs_queue.dlq[0].arn : null
  }
}

# Target: SNS notification for high severity findings
resource "aws_cloudwatch_event_target" "guardduty_high_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_high.name
  target_id = "SecurityNotificationsTopic"
  arn       = aws_sns_topic.security_notifications.arn
}

# ========================================
# EventBridge Rules for AWS Config
# ========================================

# Rule for S3 bucket public access violations
resource "aws_cloudwatch_event_rule" "config_s3_public" {
  name        = "security-automation-config-s3-public"
  description = "Capture S3 buckets made public"

  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      configRuleName = ["s3-bucket-public-read-prohibited", "s3-bucket-public-write-prohibited"]
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT"]
      }
    }
  })

  tags = merge(
    local.common_tags,
    {
      Name = "config-s3-public-rule"
    }
  )
}

# Target: Lambda function for S3 remediation
resource "aws_cloudwatch_event_target" "config_s3_lambda" {
  rule      = aws_cloudwatch_event_rule.config_s3_public.name
  target_id = "S3RemediationLambda"
  arn       = aws_lambda_function.s3_remediation.arn

  retry_policy {
    maximum_retry_attempts = 2
    maximum_event_age      = 3600
  }

  dead_letter_config {
    arn = var.enable_dlq ? aws_sqs_queue.dlq[0].arn : null
  }
}

# Target: SNS notification for Config violations
resource "aws_cloudwatch_event_target" "config_s3_sns" {
  rule      = aws_cloudwatch_event_rule.config_s3_public.name
  target_id = "SecurityNotificationsTopic"
  arn       = aws_sns_topic.security_notifications.arn

  input_transformer {
    input_paths = {
      rule       = "$.detail.configRuleName"
      resourceId = "$.detail.resourceId"
      compliance = "$.detail.newEvaluationResult.complianceType"
      time       = "$.time"
    }

    input_template = <<EOF
{
  "alert_type": "AWS Config Compliance Violation",
  "config_rule": <rule>,
  "resource_id": <resourceId>,
  "compliance_status": <compliance>,
  "timestamp": <time>,
  "action": "Automated remediation triggered"
}
EOF
  }
}

# ========================================
# EventBridge Permissions for Lambda
# ========================================

# Permission for EventBridge to invoke GuardDuty remediation Lambda
resource "aws_lambda_permission" "allow_eventbridge_guardduty" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.guardduty_remediation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_critical.arn
}

resource "aws_lambda_permission" "allow_eventbridge_guardduty_high" {
  statement_id  = "AllowExecutionFromEventBridgeHigh"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.guardduty_remediation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_high.arn
}

# Permission for EventBridge to invoke S3 remediation Lambda
resource "aws_lambda_permission" "allow_eventbridge_config" {
  statement_id  = "AllowExecutionFromEventBridgeConfig"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_remediation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.config_s3_public.arn
}

# Permission for EventBridge to invoke Slack notifier Lambda
resource "aws_lambda_permission" "allow_sns_slack" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.security_notifications.arn
}
