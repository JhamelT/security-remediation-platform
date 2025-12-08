# Deployment Guide - AWS Security Automation Platform

## Prerequisites

Before deploying, ensure you have:

1. **AWS Account** with administrative access
2. **AWS CLI** configured with credentials
   ```bash
   aws configure
   aws sts get-caller-identity  # Verify credentials
   ```
3. **Terraform 1.5+** installed
   ```bash
   terraform version
   ```
4. **Python 3.12+** for Lambda development (optional)
5. **Slack Workspace** with incoming webhook configured (optional)

---

## Step 1: Clone Repository

```bash
git clone https://github.com/yourusername/aws-security-automation.git
cd aws-security-automation
```

---

## Step 2: Configure Slack Webhook (Optional)

### Create Slack Incoming Webhook

1. Go to https://api.slack.com/apps
2. Click "Create New App" → "From scratch"
3. Name: `Security Automation`, select your workspace
4. Navigate to "Incoming Webhooks" → Toggle "Activate Incoming Webhooks" ON
5. Click "Add New Webhook to Workspace"
6. Select channel (e.g., `#security-alerts`)
7. Copy webhook URL (format: `https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX`)

### Test Webhook (Optional)

```bash
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"🔒 Security Automation Platform - Test Message"}' \
  YOUR_WEBHOOK_URL
```

---

## Step 3: Configure Terraform Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
# Required
aws_region         = "us-east-1"           # Your AWS region
slack_webhook_url  = "https://hooks.slack.com/services/..."  # From Step 2
notification_email = "security@yourdomain.com"                # Your email

# Optional (use defaults or customize)
environment               = "prod"
lambda_timeout            = 60
lambda_memory             = 256
enable_guardduty          = true
log_retention_days        = 30
enable_dlq                = true
```

**Security Note:** Never commit `terraform.tfvars` to version control! It's already in `.gitignore`.

---

## Step 4: Initialize Terraform

```bash
terraform init
```

**Expected Output:**
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.x.x...

Terraform has been successfully initialized!
```

---

## Step 5: Review Deployment Plan

```bash
terraform plan
```

**What This Shows:**
- All AWS resources that will be created (~15 resources)
- GuardDuty detector configuration
- EventBridge rules for security events
- Lambda functions for remediation
- SNS topic and subscriptions
- IAM roles and policies
- CloudWatch log groups
- S3 bucket for GuardDuty findings

**Review Carefully:**
- Ensure `aws_region` matches your target region
- Verify resource names follow your naming conventions
- Check that no unintended resources will be modified

---

## Step 6: Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted to confirm deployment.

**Deployment Time:** ~5-7 minutes

**Expected Output:**
```
Apply complete! Resources: 15 added, 0 changed, 0 destroyed.

Outputs:
account_id = "123456789012"
deployment_region = "us-east-1"
guardduty_detector_id = "abc123def456"
sns_topic_arn = "arn:aws:sns:us-east-1:123456789012:security-automation-notifications"
...
```

---

## Step 7: Confirm Email Subscription

1. Check your email inbox (specified in `notification_email`)
2. Look for message: **"AWS Notification - Subscription Confirmation"**
3. Click **"Confirm subscription"** link
4. You should see: **"Subscription confirmed!"**

**If you don't see the email:**
- Check spam folder
- Verify email address in `terraform.tfvars`
- Redeploy: `terraform apply`

---

## Step 8: Verify Deployment

### 8.1 Check GuardDuty Status

```bash
aws guardduty list-detectors
```

**Expected Output:**
```json
{
    "DetectorIds": [
        "abc123def456"
    ]
}
```

Get detector details:
```bash
DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
aws guardduty get-detector --detector-id $DETECTOR_ID
```

### 8.2 Verify EventBridge Rules

```bash
aws events list-rules --name-prefix security-automation
```

**Expected Rules:**
- `security-automation-guardduty-critical`
- `security-automation-guardduty-high`
- `security-automation-config-s3-public`

Get rule details:
```bash
aws events describe-rule --name security-automation-guardduty-critical
```

### 8.3 Check Lambda Functions

```bash
aws lambda list-functions --query 'Functions[?contains(FunctionName, `security`)].FunctionName'
```

**Expected Functions:**
- `security-remediation-guardduty`
- `security-remediation-s3`
- `security-slack-notifier`

Test Lambda invocation permissions:
```bash
aws lambda get-policy --function-name security-remediation-guardduty
```

### 8.4 Verify SNS Topic

```bash
aws sns list-topics --query 'Topics[?contains(TopicArn, `security`)]'
```

Check subscriptions:
```bash
SNS_TOPIC_ARN=$(terraform output -raw sns_topic_arn)
aws sns list-subscriptions-by-topic --topic-arn $SNS_TOPIC_ARN
```

**Expected Subscriptions:**
- Email (PendingConfirmation or Confirmed)
- Lambda (security-slack-notifier)

---

## Step 9: Test Security Event Response

### 9.1 Create Test S3 Bucket

```bash
# Create test bucket
TEST_BUCKET="security-test-$(date +%s)"
aws s3 mb s3://$TEST_BUCKET

# Make it public (triggers Config rule violation)
aws s3api put-bucket-acl --bucket $TEST_BUCKET --acl public-read

echo "Created test bucket: $TEST_BUCKET"
```

### 9.2 Enable AWS Config (If Not Already Enabled)

If AWS Config is not set up:

```bash
# Create Config S3 bucket
CONFIG_BUCKET="aws-config-$(aws sts get-caller-identity --query Account --output text)"
aws s3 mb s3://$CONFIG_BUCKET

# Create Config recorder (simplified - see AWS docs for full setup)
aws configservice put-configuration-recorder \
  --configuration-recorder name=default,roleARN=arn:aws:iam::ACCOUNT_ID:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig \
  --recording-group allSupported=true,includeGlobalResourceTypes=true

aws configservice start-configuration-recorder --configuration-recorder-name default
```

Add Config rules:
```bash
aws configservice put-config-rule \
  --config-rule '{
    "ConfigRuleName": "s3-bucket-public-read-prohibited",
    "Source": {
      "Owner": "AWS",
      "SourceIdentifier": "S3_BUCKET_PUBLIC_READ_PROHIBITED"
    }
  }'
```

### 9.3 Monitor Remediation

Watch CloudWatch Logs:
```bash
# GuardDuty remediation logs
aws logs tail /aws/lambda/security-remediation-guardduty --follow

# S3 remediation logs (in separate terminal)
aws logs tail /aws/lambda/security-remediation-s3 --follow
```

Check if bucket was remediated:
```bash
# Wait 2-3 minutes for Config evaluation, then check:
aws s3api get-public-access-block --bucket $TEST_BUCKET
```

**Expected Output (after remediation):**
```json
{
    "PublicAccessBlockConfiguration": {
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }
}
```

### 9.4 Check Notifications

- **Email:** Look for subject "🔒 S3 Remediation: security-test-..."
- **Slack:** Check your `#security-alerts` channel for formatted message

### 9.5 Clean Up Test Resources

```bash
# Delete test bucket
aws s3 rb s3://$TEST_BUCKET --force

echo "Test bucket deleted: $TEST_BUCKET"
```

---

## Step 10: Production Hardening (Optional)

### 10.1 Enable MFA Delete on S3 Buckets

```bash
# For GuardDuty findings bucket
aws s3api put-bucket-versioning \
  --bucket guardduty-findings-ACCOUNT_ID-REGION \
  --versioning-configuration Status=Enabled,MFADelete=Enabled \
  --mfa "SERIAL_NUMBER MFA_CODE"
```

### 10.2 Enable CloudTrail (If Not Already)

```bash
# Create CloudTrail trail
aws cloudtrail create-trail \
  --name security-automation-trail \
  --s3-bucket-name cloudtrail-logs-ACCOUNT_ID
  
aws cloudtrail start-logging --name security-automation-trail
```

### 10.3 Set Up Cross-Account Access (For Multi-Account Environments)

See `docs/multi-account.md` for detailed instructions.

---

## Monitoring & Operations

### Check Lambda Execution

```bash
# View recent invocations
aws lambda get-function --function-name security-remediation-guardduty \
  --query 'Configuration.[LastModified,CodeSize,Timeout,MemorySize]'

# View CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=security-remediation-guardduty \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-12-31T23:59:59Z \
  --period 3600 \
  --statistics Sum
```

### Check Dead Letter Queue (If Enabled)

```bash
# Check for failed events
DLQ_URL=$(terraform output -raw dlq_url)
aws sqs receive-message --queue-url $DLQ_URL
```

### Review GuardDuty Findings

```bash
DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
aws guardduty list-findings --detector-id $DETECTOR_ID
```

---

## Troubleshooting

### Issue: Email Subscription Not Confirmed

**Solution:**
```bash
# Resend confirmation email
SNS_TOPIC_ARN=$(terraform output -raw sns_topic_arn)
aws sns subscribe \
  --topic-arn $SNS_TOPIC_ARN \
  --protocol email \
  --notification-endpoint your-email@example.com
```

### Issue: Lambda Timeout Errors

**Solution:** Increase timeout in `terraform.tfvars`:
```hcl
lambda_timeout = 120  # Increase to 2 minutes
```

Then redeploy:
```bash
terraform apply
```

### Issue: GuardDuty Not Generating Findings

**Solution:** GuardDuty findings can take 6-24 hours to appear in new accounts. For testing, you can generate sample findings:

```bash
DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
aws guardduty create-sample-findings \
  --detector-id $DETECTOR_ID \
  --finding-types UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.InsideAWS
```

### Issue: EventBridge Rule Not Triggering

**Solution:** Test event pattern manually:
```bash
aws events test-event-pattern \
  --event-pattern file://test-event-pattern.json \
  --event file://sample-guardduty-finding.json
```

---

## Updating the Platform

To update Lambda code or infrastructure:

```bash
# Make code changes
vim lambda/guardduty_remediation.py

# Plan changes
terraform plan

# Apply updates
terraform apply
```

---

## Destroying Infrastructure

**⚠️ WARNING:** This will delete all security automation resources.

```bash
cd terraform
terraform destroy
```

Type `yes` to confirm deletion.

**Manual Cleanup Required:**
- GuardDuty findings in S3 (retained by lifecycle policy)
- CloudWatch log data beyond retention period
- Any quarantined EC2 instances

---

## Cost Estimates

**Monthly Costs (Single Account):**
- GuardDuty: ~$4.59 (1M CloudTrail events)
- Lambda: ~$0.50 (5,000 invocations/month)
- EventBridge: ~$0.10 (100K events)
- SNS: ~$0.05 (1,000 notifications)
- S3 Storage: ~$0.50 (10GB GuardDuty findings)
- CloudWatch Logs: ~$1.00 (5GB logs)

**Total:** ~$7-10/month per account

---

## Next Steps

1. **Phase 2:** Deploy Step Functions for conditional approval workflows
2. **Phase 3:** Set up multi-account aggregation with Security Hub
3. **Phase 4:** Build CloudWatch dashboards for MTTR metrics
4. **Production:** Enable AWS Config rules for comprehensive compliance

See `README.md` for project roadmap and feature details.

---

## Support

- **GitHub Issues:** https://github.com/yourusername/aws-security-automation/issues
- **Documentation:** See `docs/` directory
- **Security Issues:** security@yourdomain.com (DO NOT open public issues)

---

**🎉 Congratulations! Your AWS Security Automation Platform is now live.**
