variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "security-remediation"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "notification_email" {
  description = "Email address for SNS notifications"
  type        = string
}

variable "enable_guardduty" {
  description = "Enable GuardDuty detector"
  type        = bool
  default     = true
}

variable "enable_config" {
  description = "Enable AWS Config recorder (Phase 2)"
  type        = bool
  default     = false
}

variable "enable_inspector" {
  description = "Enable AWS Inspector (Phase 2)"
  type        = bool
  default     = false
}

variable "auto_remediate_high_severity" {
  description = "Automatically remediate high severity findings without approval"
  type        = bool
  default     = true
}

variable "lambda_log_retention_days" {
  description = "CloudWatch Logs retention for Lambda functions"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "SecurityRemediation"
    ManagedBy   = "Terraform"
    Purpose     = "AutomatedSecurityResponse"
  }
}
