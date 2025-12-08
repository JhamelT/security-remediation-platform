output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = var.enable_guardduty ? aws_guardduty_detector.main[0].id : null
}

output "sns_topic_arn" {
  description = "SNS topic ARN for security alerts"
  value       = aws_sns_topic.security_alerts.arn
}

output "lambda_function_name" {
  description = "Remediation Lambda function name"
  value       = aws_lambda_function.credential_remediation.function_name
}

output "lambda_function_arn" {
  description = "Remediation Lambda function ARN"
  value       = aws_lambda_function.credential_remediation.arn
}

output "lambda_log_group" {
  description = "CloudWatch Log Group for Lambda function"
  value       = aws_cloudwatch_log_group.remediation_lambda.name
}

output "eventbridge_rule_name" {
  description = "EventBridge rule name for GuardDuty findings"
  value       = aws_cloudwatch_event_rule.guardduty_findings.name
}

output "account_id" {
  description = "AWS Account ID"
  value       = local.account_id
}

output "region" {
  description = "AWS Region"
  value       = local.region
}

output "test_commands" {
  description = "Commands to test the security remediation platform"
  value = <<-EOT
    # View Lambda logs:
    aws logs tail /aws/lambda/${aws_lambda_function.credential_remediation.function_name} --follow

    # List GuardDuty findings:
    aws guardduty list-findings --detector-id ${var.enable_guardduty ? aws_guardduty_detector.main[0].id : "DETECTOR_ID"}

    # Create test IAM user for simulated compromise:
    aws iam create-user --user-name test-compromised-user
    aws iam create-access-key --user-name test-compromised-user

    # View EventBridge rule:
    aws events describe-rule --name ${aws_cloudwatch_event_rule.guardduty_findings.name}
  EOT
}
