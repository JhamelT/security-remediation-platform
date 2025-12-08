output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = try(aws_guardduty_detector.main[0].id, "Not enabled")
}

output "sns_topic_arn" {
  description = "SNS topic ARN for security notifications"
  value       = aws_sns_topic.security_notifications.arn
}

output "eventbridge_rule_arns" {
  description = "EventBridge rule ARNs"
  value = {
    guardduty_critical = aws_cloudwatch_event_rule.guardduty_critical.arn
    guardduty_high     = aws_cloudwatch_event_rule.guardduty_high.arn
  }
}

output "lambda_function_arns" {
  description = "Lambda function ARNs"
  value = {
    guardduty_remediation = aws_lambda_function.guardduty_remediation.arn
    s3_remediation        = aws_lambda_function.s3_remediation.arn
  }
}

output "lambda_log_groups" {
  description = "CloudWatch log group names for Lambda functions"
  value = {
    guardduty_remediation = aws_cloudwatch_log_group.guardduty_remediation.name
    s3_remediation        = aws_cloudwatch_log_group.s3_remediation.name
  }
}

output "dlq_url" {
  description = "Dead Letter Queue URL"
  value       = try(aws_sqs_queue.dlq[0].url, "DLQ not enabled")
}

output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}
