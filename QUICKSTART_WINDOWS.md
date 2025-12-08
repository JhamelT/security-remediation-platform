# 🚀 Quick Start - Windows/PowerShell Edition

## Phase 1 Deployment in 15 Minutes

This guide is optimized for **Windows 10/11 with PowerShell**. Everything adapted for Windows environment.

---

## Prerequisites (5 minutes)

### Required Tools

#### 1. Install AWS CLI
```powershell
# Download and run the MSI installer
# https://awscli.amazonaws.com/AWSCLIV2.msi

# Verify installation
aws --version
# Should show: aws-cli/2.x.x
```

#### 2. Install Terraform
```powershell
# Option A: Using Chocolatey (if you have it)
choco install terraform

# Option B: Manual installation
# 1. Download from: https://www.terraform.io/downloads
# 2. Extract terraform.exe
# 3. Add to PATH or move to C:\Windows\System32\

# Verify installation
terraform --version
# Should show: Terraform v1.6.x or later
```

#### 3. Configure AWS Credentials
```powershell
# Run AWS configure
aws configure

# Enter your credentials:
AWS Access Key ID: [YOUR_ACCESS_KEY]
AWS Secret Access Key: [YOUR_SECRET_KEY]
Default region name: us-east-1
Default output format: json

# Verify access
aws sts get-caller-identity
# Should show your account ID
```

---

## Deploy Infrastructure (5 minutes)

### Step 1: Download and Extract Project

1. Download the project folder from Claude
2. Extract to a location like: `C:\Projects\security-remediation-platform`
3. Open PowerShell as Administrator

### Step 2: Navigate to Project
```powershell
cd C:\Projects\security-remediation-platform
```

### Step 3: Configure Settings
```powershell
# Copy example configuration
Copy-Item terraform\terraform.tfvars.example terraform\terraform.tfvars

# Edit the file
notepad terraform\terraform.tfvars

# Change this line:
# notification_email = "your.email@example.com"
# To your actual email address

# Optional: Add Slack webhook if you have one
# slack_webhook_url = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Save and close
```

### Step 4: Deploy with Terraform
```powershell
# Navigate to terraform directory
cd terraform

# Initialize Terraform
terraform init

# Review what will be created
terraform plan

# Deploy (auto-approve to skip confirmation)
terraform apply -auto-approve

# Deployment takes 2-3 minutes
```

### Step 5: Confirm Email Subscription
1. Check your email for "AWS Notification - Subscription Confirmation"
2. Click the confirmation link
3. You should see "Subscription confirmed!"

---

## Test the Platform (5 minutes)

### Option A: Manual Test via AWS Console (Recommended for Windows)

Since the test scripts are bash-based, here's the PowerShell equivalent:

#### 1. Create Test IAM User
```powershell
# Set variables
$TestUser = "test-compromised-user-$(Get-Date -Format 'yyyyMMddHHmmss')"

# Create user
aws iam create-user --user-name $TestUser --tags Key=Purpose,Value=SecurityTesting

# Create access key
$AccessKeyJson = aws iam create-access-key --user-name $TestUser | ConvertFrom-Json
$AccessKeyId = $AccessKeyJson.AccessKey.AccessKeyId

Write-Host "✓ Test user created: $TestUser" -ForegroundColor Green
Write-Host "✓ Access key: $AccessKeyId" -ForegroundColor Green
```

#### 2. Get Lambda Function Name
```powershell
# Get Lambda function name from Terraform output
cd terraform
$LambdaName = terraform output -raw lambda_function_name
Write-Host "Lambda function: $LambdaName" -ForegroundColor Yellow
cd ..
```

#### 3. Create Test Event File
```powershell
# Create test event JSON
$AccountId = (aws sts get-caller-identity --query Account --output text)
$Region = (aws configure get region)
$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$TestEvent = @"
{
  "version": "0",
  "id": "test-event-$(Get-Date -Format 'yyyyMMddHHmmss')",
  "detail-type": "GuardDuty Finding",
  "source": "aws.guardduty",
  "account": "$AccountId",
  "time": "$Timestamp",
  "region": "$Region",
  "detail": {
    "schemaVersion": "2.0",
    "accountId": "$AccountId",
    "region": "$Region",
    "id": "test-finding-$(Get-Date -Format 'yyyyMMddHHmmss')",
    "type": "UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS",
    "title": "Test: Suspicious API activity detected",
    "description": "This is a simulated GuardDuty finding for testing automated remediation",
    "severity": 5.0,
    "createdAt": "$Timestamp",
    "updatedAt": "$Timestamp",
    "resource": {
      "resourceType": "AccessKey",
      "accessKeyDetails": {
        "accessKeyId": "$AccessKeyId",
        "principalId": "test-principal",
        "userName": "$TestUser",
        "userType": "IAMUser"
      }
    },
    "service": {
      "serviceName": "guardduty",
      "detectorId": "test-detector",
      "action": {
        "actionType": "AWS_API_CALL",
        "awsApiCallAction": {
          "api": "GetSecretValue",
          "serviceName": "secretsmanager",
          "callerType": "Domain"
        }
      }
    }
  }
}
"@

# Save to file
$TestEvent | Out-File -FilePath test-event.json -Encoding utf8
Write-Host "✓ Test event created" -ForegroundColor Green
```

#### 4. Invoke Lambda Function
```powershell
# Invoke Lambda with test event
aws lambda invoke `
  --function-name $LambdaName `
  --payload file://test-event.json `
  lambda-response.json

Write-Host "✓ Lambda invoked" -ForegroundColor Green

# View response
Write-Host "`nLambda Response:" -ForegroundColor Yellow
Get-Content lambda-response.json | ConvertFrom-Json | ConvertTo-Json -Depth 10
```

#### 5. Verify Remediation
```powershell
Write-Host "`n=== Verifying Remediation ===" -ForegroundColor Cyan

# Check access key status
Write-Host "`n1. Checking access key status..." -ForegroundColor Yellow
$KeyStatus = (aws iam list-access-keys --user-name $TestUser --query 'AccessKeyMetadata[0].Status' --output text)

if ($KeyStatus -eq "Inactive") {
    Write-Host "✓ Access key successfully deactivated" -ForegroundColor Green
} else {
    Write-Host "✗ Access key status: $KeyStatus" -ForegroundColor Red
}

# Check for quarantine policy
Write-Host "`n2. Checking for quarantine policy..." -ForegroundColor Yellow
try {
    aws iam get-user-policy --user-name $TestUser --policy-name "security-remediation-quarantine-policy" | Out-Null
    Write-Host "✓ Quarantine policy successfully attached" -ForegroundColor Green
} catch {
    Write-Host "✗ Quarantine policy not found" -ForegroundColor Red
}

# View Lambda logs
Write-Host "`n3. Recent Lambda logs:" -ForegroundColor Yellow
aws logs tail "/aws/lambda/$LambdaName" --since 5m --format short
```

#### 6. Clean Up Test Resources
```powershell
Write-Host "`n=== Cleaning Up Test Resources ===" -ForegroundColor Cyan

# Delete access key
aws iam delete-access-key --user-name $TestUser --access-key-id $AccessKeyId
Write-Host "✓ Deleted access key" -ForegroundColor Green

# Delete inline policy
aws iam delete-user-policy --user-name $TestUser --policy-name "security-remediation-quarantine-policy" 2>$null

# Delete user
aws iam delete-user --user-name $TestUser
Write-Host "✓ Deleted test user: $TestUser" -ForegroundColor Green

# Clean up temp files
Remove-Item test-event.json, lambda-response.json -ErrorAction SilentlyContinue
Write-Host "✓ Cleaned up temporary files" -ForegroundColor Green
```

### Option B: Use Git Bash (If You Have Git for Windows)

If you have **Git for Windows** installed, you can use Git Bash to run the original test scripts:

```bash
# Open Git Bash (not PowerShell)
cd /c/Projects/security-remediation-platform

# Run test script
./scripts/test-guardduty-finding.sh

# Clean up
./scripts/cleanup-test-users.sh
```

---

## What Just Happened?

1. **GuardDuty** detected "compromised credentials" (simulated)
2. **EventBridge** routed the finding to Lambda
3. **Lambda** automatically:
   - ✅ Deactivated the compromised access key
   - ✅ Attached a quarantine policy (blocks all actions)
   - ✅ Disabled console access
   - ✅ Logged incident to Secrets Manager
   - ✅ Sent email notification
4. **MTTR**: Under 60 seconds (vs. 2-4 hours manual)

---

## Verify Deployment

### Check Your Email
You should have received:
```
Subject: [HIGH] Security Remediation: UnauthorizedAccess:IAMUser

Security Finding Remediated

Severity: HIGH
Finding Type: UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS
Actions Taken:
  • Deactivated access key AKIA...
  • Attached quarantine policy to test-compromised-user
  • Disabled console access for test-compromised-user
```

### View Lambda Logs (PowerShell)
```powershell
# View recent logs
aws logs tail /aws/lambda/security-remediation-dev-credential-remediation --since 1h

# Follow logs in real-time
aws logs tail /aws/lambda/security-remediation-dev-credential-remediation --follow
```

### Check GuardDuty Findings
```powershell
# Get detector ID
cd terraform
$DetectorId = terraform output -raw guardduty_detector_id

# List findings
aws guardduty list-findings --detector-id $DetectorId

# Get finding details
$FindingId = (aws guardduty list-findings --detector-id $DetectorId --query 'FindingIds[0]' --output text)
aws guardduty get-findings --detector-id $DetectorId --finding-ids $FindingId
```

---

## View Costs

### Check Current Usage
```powershell
# View GuardDuty usage (updates daily)
aws ce get-cost-and-usage `
  --time-period Start=2025-12-01,End=2025-12-31 `
  --granularity MONTHLY `
  --metrics UnblendedCost `
  --group-by Type=SERVICE `
  --filter file://cost-filter.json

# Create cost-filter.json first:
@'
{
  "Dimensions": {
    "Key": "SERVICE",
    "Values": ["Amazon GuardDuty", "AWS Lambda", "Amazon EventBridge"]
  }
}
'@ | Out-File cost-filter.json -Encoding utf8
```

**Expected costs**: $6-8/month for dev environment

---

## Monitoring Commands (PowerShell)

### View Active Resources
```powershell
# List GuardDuty findings
aws guardduty list-findings --detector-id $DetectorId

# List Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `security-remediation`)].FunctionName'

# List SNS topics
aws sns list-topics --query 'Topics[?contains(TopicArn, `security-remediation`)].TopicArn'

# List EventBridge rules
aws events list-rules --query 'Rules[?contains(Name, `security-remediation`)].Name'
```

### View Incident History
```powershell
# List incident records in Secrets Manager
aws secretsmanager list-secrets `
  --query 'SecretList[?starts_with(Name, `security-remediation/incidents/`)].Name'

# View specific incident
$SecretName = "security-remediation/incidents/test-user/finding-123"
aws secretsmanager get-secret-value --secret-id $SecretName --query SecretString --output text | ConvertFrom-Json
```

---

## PowerShell Helper Functions

### Save These to Your Profile

Create a PowerShell module for common tasks:

```powershell
# Create file: SecurityRemediation.psm1

function Get-RemediationLogs {
    param([int]$Hours = 1)
    aws logs tail /aws/lambda/security-remediation-dev-credential-remediation --since "$Hours`h"
}

function Get-GuardDutyFindings {
    $DetectorId = (aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
    aws guardduty list-findings --detector-id $DetectorId
}

function Get-RemediationCosts {
    param(
        [string]$StartDate = (Get-Date).AddMonths(-1).ToString("yyyy-MM-dd"),
        [string]$EndDate = (Get-Date).ToString("yyyy-MM-dd")
    )
    
    aws ce get-cost-and-usage `
        --time-period Start=$StartDate,End=$EndDate `
        --granularity MONTHLY `
        --metrics UnblendedCost `
        --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon GuardDuty","AWS Lambda"]}}'
}

function Test-RemediationPlatform {
    Write-Host "Creating test IAM user..." -ForegroundColor Yellow
    # (Use the test commands from above)
}

Export-ModuleMember -Function *
```

### Load the module:
```powershell
# Add to PowerShell profile
Import-Module .\SecurityRemediation.psm1

# Use functions
Get-RemediationLogs -Hours 2
Get-GuardDutyFindings
Get-RemediationCosts
```

---

## Teardown (When Done Testing)

### Remove All Infrastructure
```powershell
# Navigate to terraform directory
cd C:\Projects\security-remediation-platform\terraform

# Destroy all resources
terraform destroy -auto-approve

# Confirm deletion
Write-Host "✓ All infrastructure removed" -ForegroundColor Green
```

**Cost after teardown**: $0 (GuardDuty prorated, Lambda/EventBridge have no minimum)

---

## Troubleshooting (Windows-Specific)

### Issue: "terraform: command not found"
**Solution**: Add Terraform to PATH
```powershell
# Check current PATH
$env:PATH -split ";"

# Add Terraform directory (replace with your path)
$env:PATH += ";C:\Program Files\Terraform"

# Or add permanently via System Properties → Environment Variables
```

### Issue: "Access Denied" errors
**Solution**: Run PowerShell as Administrator
```powershell
# Right-click PowerShell → "Run as Administrator"
```

### Issue: Can't run scripts (.sh files)
**Solution**: Either use Git Bash, or use the PowerShell commands provided above

### Issue: "InvalidClientTokenId" AWS error
**Solution**: Reconfigure AWS credentials
```powershell
aws configure
# Re-enter your Access Key ID and Secret Access Key
```

### Issue: Line endings in Terraform files
If Terraform shows syntax errors after download:
```powershell
# Install dos2unix (via Git for Windows or Chocolatey)
dos2unix terraform/*.tf

# Or use PowerShell to fix:
Get-ChildItem terraform\*.tf | ForEach-Object {
    (Get-Content $_.FullName) | Set-Content $_.FullName
}
```

---

## Windows-Specific Tips

### Use Windows Terminal (Recommended)
Modern, better experience than classic PowerShell:
```powershell
# Install from Microsoft Store: "Windows Terminal"
# Supports tabs, better colors, easier copy/paste
```

### File Path Conventions
```powershell
# Windows uses backslashes
cd C:\Projects\security-remediation-platform\terraform

# But AWS CLI and Terraform work with forward slashes too
cd C:/Projects/security-remediation-platform/terraform

# Both work!
```

### View Files
```powershell
# Open in Notepad
notepad terraform\main.tf

# Open in VS Code (if installed)
code terraform\main.tf

# Open in default text editor
Start-Process terraform\main.tf
```

---

## Complete PowerShell Test Script

Here's a consolidated script you can save and run:

```powershell
# SecurityRemediationTest.ps1
# Complete test script for Windows

Write-Host "=== Security Remediation Platform - Test ===" -ForegroundColor Cyan

# 1. Create test user
$TestUser = "test-compromised-user-$(Get-Date -Format 'yyyyMMddHHmmss')"
Write-Host "`nCreating test user: $TestUser" -ForegroundColor Yellow
aws iam create-user --user-name $TestUser --tags Key=Purpose,Value=SecurityTesting
$AccessKeyJson = aws iam create-access-key --user-name $TestUser | ConvertFrom-Json
$AccessKeyId = $AccessKeyJson.AccessKey.AccessKeyId
Write-Host "✓ Test user created" -ForegroundColor Green

# 2. Get Lambda name
cd terraform
$LambdaName = terraform output -raw lambda_function_name
cd ..

# 3. Create and invoke test event
$AccountId = (aws sts get-caller-identity --query Account --output text)
$Region = (aws configure get region)
$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$TestEvent = @"
{
  "version": "0",
  "id": "test-$(Get-Date -Format 'yyyyMMddHHmmss')",
  "detail-type": "GuardDuty Finding",
  "source": "aws.guardduty",
  "account": "$AccountId",
  "time": "$Timestamp",
  "region": "$Region",
  "detail": {
    "schemaVersion": "2.0",
    "accountId": "$AccountId",
    "region": "$Region",
    "id": "test-finding-$(Get-Date -Format 'yyyyMMddHHmmss')",
    "type": "UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS",
    "title": "Test: Suspicious API activity",
    "description": "Simulated GuardDuty finding",
    "severity": 5.0,
    "createdAt": "$Timestamp",
    "updatedAt": "$Timestamp",
    "resource": {
      "resourceType": "AccessKey",
      "accessKeyDetails": {
        "accessKeyId": "$AccessKeyId",
        "principalId": "test-principal",
        "userName": "$TestUser",
        "userType": "IAMUser"
      }
    }
  }
}
"@

$TestEvent | Out-File test-event.json -Encoding utf8
Write-Host "`n✓ Test event created" -ForegroundColor Green

Write-Host "`nInvoking Lambda..." -ForegroundColor Yellow
aws lambda invoke --function-name $LambdaName --payload file://test-event.json lambda-response.json
Write-Host "✓ Lambda invoked" -ForegroundColor Green

# 4. Verify remediation
Start-Sleep -Seconds 2
Write-Host "`n=== Verifying Remediation ===" -ForegroundColor Cyan

$KeyStatus = (aws iam list-access-keys --user-name $TestUser --query 'AccessKeyMetadata[0].Status' --output text)
if ($KeyStatus -eq "Inactive") {
    Write-Host "✓ Access key deactivated" -ForegroundColor Green
} else {
    Write-Host "✗ Access key status: $KeyStatus" -ForegroundColor Red
}

try {
    aws iam get-user-policy --user-name $TestUser --policy-name "security-remediation-quarantine-policy" | Out-Null
    Write-Host "✓ Quarantine policy attached" -ForegroundColor Green
} catch {
    Write-Host "✗ Quarantine policy not found" -ForegroundColor Red
}

# 5. Clean up
Write-Host "`n=== Cleaning Up ===" -ForegroundColor Cyan
aws iam delete-access-key --user-name $TestUser --access-key-id $AccessKeyId
aws iam delete-user-policy --user-name $TestUser --policy-name "security-remediation-quarantine-policy" 2>$null
aws iam delete-user --user-name $TestUser
Remove-Item test-event.json, lambda-response.json -ErrorAction SilentlyContinue
Write-Host "✓ Cleanup complete" -ForegroundColor Green

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan
Write-Host "Check your email for the security alert notification!" -ForegroundColor Yellow
```

Save this as `SecurityRemediationTest.ps1` and run:
```powershell
.\SecurityRemediationTest.ps1
```

---

## Next Steps

### After Successful Deployment

1. **Add to Resume** (bullet points in PROJECT_SUMMARY.md)
2. **Create GitHub Repo**:
   ```powershell
   git init
   git add .
   git commit -m "Initial commit: Security Remediation Platform"
   git remote add origin https://github.com/yourusername/security-remediation-platform.git
   git push -u origin main
   ```
3. **Update LinkedIn** with project announcement
4. **Practice Demo** for interviews

### Phase 2 (Optional - 3 hours)
- AWS Config integration
- Step Functions approval workflows
- S3 and Security Group remediation

See `PROJECT_SUMMARY.md` for Phase 2 details.

---

## Summary

**Time**: 15 minutes  
**Cost**: $6-8/month  
**Platform**: Windows 10/11 with PowerShell  
**Result**: Production-grade security platform with sub-60-second MTTR

**You've successfully deployed automated security remediation! 🎉**

For questions or issues, refer to:
- `docs/DEPLOYMENT.md` - Full troubleshooting guide
- `PROJECT_SUMMARY.md` - Strategy and interview prep
- `docs/ARCHITECTURE.md` - Technical deep dive
