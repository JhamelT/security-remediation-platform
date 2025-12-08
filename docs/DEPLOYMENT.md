# Security Remediation Platform - Deployment Guide

## Prerequisites

### Required Tools
- **AWS CLI** v2.x or later ([Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))
- **Terraform** >= 1.6 ([Installation Guide](https://developer.hashicorp.com/terraform/install))
- **jq** (for test scripts) - `brew install jq` or `apt-get install jq`

### AWS Requirements
- AWS Account with administrative access
- AWS CLI configured with credentials:
  ```bash
  aws configure
  # Or use environment variables:
  export AWS_ACCESS_KEY_ID="your-key"
  export AWS_SECRET_ACCESS_KEY="your-secret"
  export AWS_DEFAULT_REGION="us-east-1"
  ```

- Verify access:
  ```bash
  aws sts get-caller-identity
  ```

### Cost Estimate
- **GuardDuty**: $4.66/month minimum (first 10GB CloudTrail events free)
- **Lambda**: <$0.50/month (generous free tier)
- **EventBridge**: <$0.10/month
- **SNS**: <$0.10/month
- **CloudWatch Logs**: ~$0.50/month (7-day retention)
- **Total: ~$6-8/month for dev environment**

Production costs scale with finding volume. No NAT Gateways required.

---

## Phase 1 Deployment: Credential Compromise Detection

### Step 1: Clone and Configure

```bash
# Clone repository
git clone <your-repo-url>
cd security-remediation-platform

# Copy example configuration
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Edit configuration
nano terraform/terraform.tfvars
```

### Step 2: Configure Variables

Edit `terraform/terraform.tfvars`:

```hcl
# Required: Your notification email
notification_email = "your.email@example.com"

# Optional: Slack webhook for real-time alerts
# Create webhook at: https://api.slack.com/messaging/webhooks
slack_webhook_url = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# AWS Region
aws_region = "us-east-1"

# Project settings
project_name = "security-remediation"
environment  = "dev"

# Feature flags (Phase 1 only)
enable_guardduty = true
enable_config    = false  # Phase 2
enable_inspector = false  # Phase 2

# Auto-remediate high severity findings (4.0+)
auto_remediate_high_severity = true

# Log retention (7 days for cost optimization)
lambda_log_retention_days = 7
```

### Step 3: Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply

# When prompted, type 'yes' to confirm
```

**Deployment takes ~2-3 minutes**

### Step 4: Confirm SNS Subscription

After deployment:
1. Check your email for "AWS Notification - Subscription Confirmation"
2. Click the confirmation link
3. You should see: "Subscription confirmed!"

### Step 5: Verify Deployment

```bash
# Get deployment outputs
terraform output

# Expected output:
# account_id = "123456789012"
# region = "us-east-1"
# guardduty_detector_id = "abc123..."
# lambda_function_name = "security-remediation-dev-credential-remediation"
# sns_topic_arn = "arn:aws:sns:us-east-1:123456789012:..."
```

### Step 6: Test Automated Remediation

```bash
# Make scripts executable
chmod +x ../scripts/test-guardduty-finding.sh
chmod +x ../scripts/cleanup-test-users.sh

# Run test scenario
cd ..
./scripts/test-guardduty-finding.sh
```

**What the test does:**
1. Creates test IAM user with access key
2. Simulates GuardDuty finding for compromised credentials
3. Triggers Lambda remediation function
4. Verifies:
   - Access key deactivated
   - Quarantine policy attached
   - SNS notification sent
   - Incident logged to Secrets Manager

### Step 7: View Results

#### CloudWatch Logs
```bash
# View Lambda execution logs
aws logs tail /aws/lambda/security-remediation-dev-credential-remediation --follow

# View recent remediations
aws logs tail /aws/lambda/security-remediation-dev-credential-remediation --since 1h
```

#### Check SNS Email
You should receive an email:
```
Subject: [HIGH] Security Remediation: UnauthorizedAccess:IAMUser

Security Finding Remediated

Severity: HIGH
Finding Type: UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS
Actions Taken:
  • Deactivated access key AKIA...
  • Attached quarantine deny policy to test-compromised-user
  • Disabled console access for test-compromised-user
```

#### Check Slack (if configured)
You should see a formatted alert with finding details and actions taken.

### Step 8: Clean Up Test Resources

```bash
# Remove test IAM users and incident records
./scripts/cleanup-test-users.sh
```

---

## Monitoring and Operations

### View Active Findings

```bash
# List all GuardDuty findings
DETECTOR_ID=$(cd terraform && terraform output -raw guardduty_detector_id)
aws guardduty list-findings --detector-id $DETECTOR_ID

# Get finding details
aws guardduty get-findings \
  --detector-id $DETECTOR_ID \
  --finding-ids <finding-id-from-above>
```

### View Remediation History

```bash
# List incident records
aws secretsmanager list-secrets \
  --query 'SecretList[?starts_with(Name, `security-remediation/incidents/`)].Name'

# View specific incident
aws secretsmanager get-secret-value \
  --secret-id security-remediation/incidents/<user>/<finding-id> \
  --query SecretString --output text | jq '.'
```

### Monitor Costs

```bash
# View GuardDuty costs (updates daily)
aws ce get-cost-and-usage \
  --time-period Start=2025-01-01,End=2025-01-31 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --filter file://cost-filter.json

# cost-filter.json:
{
  "Dimensions": {
    "Key": "SERVICE",
    "Values": ["Amazon GuardDuty"]
  }
}
```

---

## Production Considerations

### 1. Enable Multi-Account Setup (Phase 3)

For enterprise environments:
- Deploy Security Hub aggregator in security account
- Configure member accounts to report to aggregator
- Use cross-account IAM roles for remediation

### 2. Customize Severity Thresholds

Edit `terraform/variables.tf`:
```hcl
variable "auto_remediate_high_severity" {
  default = false  # Require manual approval for high severity
}
```

### 3. Add Approval Workflow (Phase 2)

For production resources:
- Use Step Functions for approval workflows
- Post to Slack with "Approve" button
- Require security team sign-off before remediation

### 4. Increase Log Retention

For compliance:
```hcl
lambda_log_retention_days = 90  # Or 365 for long-term audit
```

### 5. Enable CloudTrail Integration

Ensure CloudTrail is enabled:
```bash
aws cloudtrail describe-trails --region us-east-1
```

GuardDuty analyzes CloudTrail events for anomalies.

---

## Troubleshooting

### Lambda Not Invoking

**Check EventBridge Rule:**
```bash
aws events list-rules --name-prefix security-remediation
aws events list-targets-by-rule --rule security-remediation-dev-guardduty-findings
```

**Verify Lambda Permissions:**
```bash
aws lambda get-policy \
  --function-name security-remediation-dev-credential-remediation
```

### No SNS Notifications

**Confirm Subscription:**
```bash
aws sns list-subscriptions-by-topic \
  --topic-arn $(cd terraform && terraform output -raw sns_topic_arn)
```

Status should be "Confirmed", not "PendingConfirmation"

### IAM Permission Errors

**Check Lambda Role:**
```bash
aws iam get-role-policy \
  --role-name security-remediation-dev-remediation-lambda-role \
  --policy-name security-remediation-dev-remediation-permissions
```

Verify policy includes:
- `iam:UpdateAccessKey`
- `iam:PutUserPolicy`
- `secretsmanager:CreateSecret`

### GuardDuty Not Generating Findings

GuardDuty uses machine learning and takes 24-48 hours to establish baseline. For testing:
- Use the test script to simulate findings
- Or create sample findings in GuardDuty console: **Protection Plans → GuardDuty → Generate Sample Findings**

---

## Teardown

### Remove All Infrastructure

```bash
cd terraform

# Clean up test users first
cd .. && ./scripts/cleanup-test-users.sh

# Destroy Terraform resources
cd terraform && terraform destroy

# When prompted, type 'yes' to confirm
```

**Cost**: $0 after teardown (GuardDuty prorated, Lambda/EventBridge have no minimum)

### Partial Cleanup (Keep Core Infrastructure)

To disable GuardDuty but keep Lambda/EventBridge for future use:

```bash
# Disable GuardDuty detector
aws guardduty update-detector \
  --detector-id $(cd terraform && terraform output -raw guardduty_detector_id) \
  --no-enable
```

This stops GuardDuty charges (~$4.66/month) while keeping automation ready.

---

## Next Steps

### Phase 2: Compliance Automation
- AWS Config rules for S3, Security Groups, IAM
- Step Functions for approval workflows
- Conditional remediation based on resource tags

### Phase 3: Multi-Account Security Hub
- Aggregate findings from 3+ AWS accounts
- Cross-account remediation via assumed roles
- Enterprise-scale security operations

### Phase 4: Advanced Features
- Inspector vulnerability remediation
- Cost optimization alerts (unused resources)
- Integration with ticketing systems (Jira, ServiceNow)

---

## Support

**GitHub Issues**: <your-repo-url>/issues  
**LinkedIn**: <your-linkedin-url>  
**Email**: <your-email>

**Documentation:**
- [AWS GuardDuty](https://docs.aws.amazon.com/guardduty/)
- [EventBridge](https://docs.aws.amazon.com/eventbridge/)
- [Lambda](https://docs.aws.amazon.com/lambda/)
