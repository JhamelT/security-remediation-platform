# AWS Automated Security Remediation Platform

**Production-grade event-driven security automation reducing Mean Time to Remediation (MTTR) from hours to seconds.**

[![AWS](https://img.shields.io/badge/AWS-GuardDuty%20%7C%20Config%20%7C%20Inspector-orange)](https://aws.amazon.com)
[![Terraform](https://img.shields.io/badge/IaC-Terraform-623CE4)](https://terraform.io)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## 🎯 Overview

This platform automatically detects and remediates security incidents across AWS environments by orchestrating responses to findings from **GuardDuty**, **AWS Config**, and **Inspector**. It eliminates manual incident response runbooks, reducing MTTR from manual investigation (hours) to automated response (seconds).

**Key Business Impact:**
- **MTTR Reduction:** Hours → <60 seconds for critical incidents
- **Compliance Automation:** Self-remediation of Config violations within SLA
- **Scale:** Multi-account architecture supporting enterprise environments
- **Audit Trail:** Complete CloudTrail logging with Slack notifications

---

## 🏗️ Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS ACCOUNT                               │
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  GuardDuty   │  │  AWS Config  │  │  Inspector   │          │
│  │   Findings   │  │    Rules     │  │   Findings   │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                  │                  │                   │
│         └─────────┬────────┴──────────────────┘                  │
│                   │                                               │
│                   ▼                                               │
│         ┌─────────────────────────┐                              │
│         │   EventBridge Rules     │                              │
│         │  (Event Patterns)       │                              │
│         └──────────┬──────────────┘                              │
│                    │                                              │
│         ┌──────────┼──────────────┐                              │
│         │          │               │                              │
│         ▼          ▼               ▼                              │
│  ┌───────────┐ ┌─────────────┐ ┌──────────────┐                │
│  │  Lambda   │ │Step Function│ │   Lambda     │                │
│  │  Auto-    │ │ Orchestrator│ │  Conditional │                │
│  │  Remediate│ │  (Approval) │ │  Logic       │                │
│  └─────┬─────┘ └──────┬──────┘ └──────┬───────┘                │
│        │               │                │                         │
│        ▼               ▼                ▼                         │
│  ┌──────────────────────────────────────────┐                   │
│  │        AWS APIs (Remediation)            │                   │
│  │  • IAM (Disable user, rotate keys)      │                   │
│  │  • S3 (Block public access)              │                   │
│  │  • Secrets Manager (Rotate credentials)  │                   │
│  │  • EC2 (Isolate instance)                │                   │
│  └──────────────────────────────────────────┘                   │
│                                                                   │
│                          │                                        │
│                          ▼                                        │
│              ┌─────────────────────┐                             │
│              │    SNS Topic        │                             │
│              │  (Notifications)    │                             │
│              └──────────┬──────────┘                             │
│                         │                                         │
└─────────────────────────┼─────────────────────────────────────┘
                          │
                          ▼
                  ┌───────────────┐
                  │  Slack / Email│
                  │  Notifications│
                  └───────────────┘
```

### Traffic Flow

1. **Detection:** GuardDuty/Config/Inspector generates security finding
2. **Event Routing:** EventBridge rule matches finding pattern, triggers Lambda/Step Function
3. **Decision Logic:** 
   - **Low/Medium severity:** Auto-remediate immediately
   - **High/Critical severity:** Step Function posts to Slack, waits for approval
4. **Remediation:** Lambda executes AWS API calls to fix issue
5. **Notification:** SNS publishes incident report to Slack/email
6. **Audit:** CloudTrail logs all actions for compliance

---

## 🚀 Features

### Phase 1: Automated Incident Response (Current)
✅ **GuardDuty Integration**
- Detects compromised IAM credentials
- Automatically disables affected IAM users
- Rotates credentials via Secrets Manager
- Sends incident notifications

✅ **EventBridge Orchestration**
- Real-time event pattern matching
- Severity-based routing
- Dead letter queue for failed events

✅ **Lambda Remediation Functions**
- Credential rotation handler
- IAM user disablement
- S3 bucket access remediation
- EC2 instance isolation

✅ **SNS Notifications**
- Slack webhook integration
- Email alerts with incident context
- Structured JSON payload for automation

### Phase 2: Step Functions Orchestration (Planned)
🔄 **Multi-Step Workflows**
- Conditional approval for high-risk actions
- Human-in-the-loop decision gates
- Parallel remediation steps
- Retry logic with exponential backoff

🔄 **AWS Config Integration**
- S3 public access detection
- Security group rule violations
- EBS encryption compliance
- Automated compliance remediation

### Phase 3: Multi-Account Architecture (Planned)
🔄 **Security Hub Aggregation**
- Central security account
- Cross-account findings aggregation
- Organizational unit (OU) level policies
- Delegated administrator setup

### Phase 4: Enhanced Observability (Planned)
🔄 **Monitoring & Dashboards**
- CloudWatch dashboard for MTTR metrics
- Lambda execution success/failure rates
- Cost tracking per remediation action
- SLA compliance reporting

---

## 🛠️ Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Security Services** | GuardDuty, Config, Inspector | Threat detection and compliance monitoring |
| **Event Processing** | EventBridge | Event routing and pattern matching |
| **Compute** | Lambda (Python 3.12) | Serverless remediation logic |
| **Orchestration** | Step Functions | Multi-step workflows with approval gates |
| **Secrets Management** | Secrets Manager | Secure credential rotation |
| **Notifications** | SNS, Slack Webhooks | Incident alerting |
| **IAC** | Terraform 1.9+ | Infrastructure as Code |
| **Observability** | CloudWatch, CloudTrail | Logging, metrics, and audit trails |

---

## 📋 Prerequisites

- **AWS Account** with admin access
- **AWS CLI** configured (`aws configure`)
- **Terraform** 1.5+ installed
- **Python 3.12+** for Lambda development
- **Slack Workspace** (optional, for notifications)

---

## 🚀 Quick Start

### 1. Clone Repository
```bash
git clone https://github.com/yourusername/aws-security-automation.git
cd aws-security-automation
```

### 2. Configure Variables
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your AWS account details
```

**Required Variables:**
```hcl
aws_region          = "us-east-1"
environment         = "prod"
slack_webhook_url   = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
notification_email  = "security-team@example.com"
```

### 3. Deploy Infrastructure
```bash
terraform init
terraform plan
terraform apply
```

**Deployment Time:** ~5 minutes  
**Resources Created:** ~15 AWS resources

### 4. Verify Deployment
```bash
# Check GuardDuty is enabled
aws guardduty list-detectors

# Verify EventBridge rules
aws events list-rules --name-prefix security-automation

# Test SNS subscription
aws sns list-subscriptions
```

### 5. Test Security Event (Optional)
```bash
# Simulate GuardDuty finding (uses sample event)
cd ../lambda
python test_guardduty_event.py
```

---

## 🧪 Testing & Validation

### Phase 1 Testing

#### Test 1: GuardDuty Credential Compromise
```bash
# Create test IAM user
aws iam create-user --user-name test-compromised-user

# Simulate GuardDuty finding (manual EventBridge test)
# Go to EventBridge console → Rules → security-automation-guardduty
# Click "Test event pattern" → Use sample GuardDuty finding

# Verify:
# 1. IAM user is disabled
# 2. Credentials rotated in Secrets Manager
# 3. SNS notification sent
```

#### Test 2: Lambda Error Handling
```bash
# Check Lambda CloudWatch logs
aws logs tail /aws/lambda/security-remediation-guardduty --follow

# Verify DLQ for failed events
aws sqs receive-message --queue-url <DLQ_URL>
```

#### Test 3: SNS Notification Delivery
```bash
# Publish test event to SNS
aws sns publish \
  --topic-arn arn:aws:sns:us-east-1:ACCOUNT:security-notifications \
  --subject "Test Alert" \
  --message "This is a test security notification"

# Check Slack channel or email inbox
```

---

## 📊 Metrics & KPIs

### Security Operations Metrics
- **MTTR:** Mean Time to Remediation (target: <60 seconds)
- **Coverage:** % of findings with automated response (target: >80%)
- **Success Rate:** % of successful remediations (target: >95%)
- **False Positive Rate:** % of unnecessary remediations (target: <5%)

### Cost Metrics
- **Lambda Invocations:** Track per-execution costs
- **EventBridge Rules:** $1/million events
- **GuardDuty:** ~$4.59/month for 1M CloudTrail events

**Estimated Monthly Cost (Single Account):** $15-25

---

## 🔐 Security Best Practices

### IAM Least Privilege
- Lambda functions use minimal IAM permissions
- Resource-level policies where possible
- No wildcard (`*`) actions in production

### Secrets Management
- Secrets Manager for all credentials
- Automatic rotation enabled
- No hardcoded secrets in code

### Network Security
- Lambda functions in VPC (optional for Phase 3)
- Private subnet deployment
- VPC endpoints for AWS service access

### Audit & Compliance
- CloudTrail logging all API calls
- S3 bucket versioning for audit logs
- 90-day log retention minimum

---

## 📚 Documentation

- [Architecture Decision Records](docs/architecture/adr-001-event-driven.md)
- [Lambda Function Guide](docs/lambda-functions.md)
- [Testing Guide](docs/testing.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Multi-Account Setup](docs/multi-account.md)

---

## 🐛 Troubleshooting

### Issue: Lambda timeout during remediation
**Symptom:** Lambda execution exceeds 15 seconds  
**Solution:** Increase timeout in `terraform/lambda.tf` or optimize API calls

### Issue: EventBridge rule not triggering
**Symptom:** No Lambda invocations after GuardDuty finding  
**Solution:** 
```bash
# Verify event pattern matches finding structure
aws events test-event-pattern \
  --event-pattern file://event-pattern.json \
  --event file://sample-finding.json
```

### Issue: SNS notifications not delivered
**Symptom:** Slack/email not receiving alerts  
**Solution:** Confirm SNS subscription via email confirmation link

---

## 🛣️ Roadmap

### Q1 2025
- [x] Phase 1: GuardDuty automation
- [ ] Phase 2: AWS Config integration
- [ ] Phase 2: Step Functions workflows

### Q2 2025
- [ ] Phase 3: Multi-account support
- [ ] Phase 4: CloudWatch dashboards
- [ ] Integration with SIEM (Splunk/Datadog)

### Q3 2025
- [ ] Machine learning for anomaly detection
- [ ] Cost optimization recommendations
- [ ] Terraform modules for reusability

---

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create feature branch (`git checkout -b feature/new-remediation`)
3. Commit changes with descriptive messages
4. Open Pull Request with context

---

## 📄 License

MIT License - see [LICENSE](LICENSE) for details

---

## 👤 Author

**Jha'Mel Thorne**  
Cloud Engineer | AWS Certified Solutions Architect & DevOps Professional

- 📧 Email: jhamel.thorne@example.com
- 💼 LinkedIn: [linkedin.com/in/jhamelthorne](https://linkedin.com/in/jhamelthorne)
- 🔗 GitHub: [github.com/jhamelthorne](https://github.com/jhamelthorne)
- 📝 Portfolio: [jhamelthorne.com](https://jhamelthorne.com)

**Open to Cloud/DevOps Opportunities** | DC-Baltimore-NYC  
Specializing in AWS infrastructure, security automation, and data-intensive workloads

---

## 🙏 Acknowledgments

- AWS Well-Architected Framework
- HashiCorp Terraform Best Practices
- SANS Institute Security Operations Guide

---

**⭐ If this project helped you, please star it on GitHub!**
