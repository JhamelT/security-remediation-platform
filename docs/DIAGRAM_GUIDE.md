# Architecture Diagram - Visual Guide

## Create Your Architecture Diagram

Use this guide to create a professional architecture diagram using [draw.io](https://app.diagrams.net/) or similar tools.

---

## Diagram Layout

### Overall Structure
```
┌─────────────────────────────────────────────────────────────────────┐
│                        AWS ACCOUNT                                   │
│                                                                      │
│  ┌──────────────────── DETECTION LAYER ────────────────────┐       │
│  │                                                          │       │
│  │  [GuardDuty]    [AWS Config]    [Inspector]            │       │
│  │                                                          │       │
│  └──────────────────────┬───────────────────────────────────┘       │
│                         │                                           │
│                         ↓                                           │
│  ┌─────────────────── EVENT PROCESSING ─────────────────┐          │
│  │                                                       │          │
│  │               [EventBridge Rules]                    │          │
│  │                                                       │          │
│  └──────────────────┬────────────┬─────────────────────┘           │
│                     │            │                                 │
│                     ↓            ↓                                 │
│  ┌────────────── ORCHESTRATION ──────────────┐                    │
│  │                                            │                    │
│  │  [Lambda]         [Step Functions]        │                    │
│  │  (Simple)         (Approval Workflow)     │                    │
│  │                                            │                    │
│  └────────────┬───────────────────────────────┘                    │
│               │                                                    │
│               ↓                                                    │
│  ┌────────── TARGET RESOURCES ──────────┐                         │
│  │                                       │                         │
│  │  • IAM Users/Keys                    │                         │
│  │  • S3 Buckets                        │                         │
│  │  • Security Groups                   │                         │
│  │  • Secrets Manager                   │                         │
│  │                                       │                         │
│  └───────────────────────────────────────┘                         │
│                                                                     │
│  ┌────────── NOTIFICATIONS ──────────┐                            │
│  │                                    │                            │
│  │  [SNS] → Email                    │                            │
│  │      → Slack                      │                            │
│  │                                    │                            │
│  └────────────────────────────────────┘                            │
│                                                                     │
│  ┌────────── AUDIT & LOGGING ───────┐                             │
│  │                                   │                             │
│  │  [CloudTrail] [CloudWatch Logs]  │                             │
│  │  [Secrets Manager]                │                             │
│  │                                   │                             │
│  └───────────────────────────────────┘                             │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Draw.io Instructions

### Step 1: Create New Diagram
1. Go to https://app.diagrams.net/
2. Choose "Create New Diagram"
3. Select "Blank Diagram"
4. Name: "Security-Remediation-Architecture"

### Step 2: Add AWS Shapes
1. Click "More Shapes" (bottom left)
2. Search for "AWS19"
3. Enable "AWS19" icon set
4. Click "Apply"

### Step 3: Build the Diagram

#### Layer 1: Detection Services (Top)
Add three AWS services horizontally:

1. **GuardDuty**
   - AWS19 → Security, Identity & Compliance → Amazon GuardDuty
   - Label: "GuardDuty\nThreat Detection"
   - Color: Orange (#FF9900)

2. **AWS Config**
   - AWS19 → Management & Governance → AWS Config
   - Label: "AWS Config\nCompliance Rules"
   - Color: Pink (#E34F45)

3. **Inspector**
   - AWS19 → Security, Identity & Compliance → Amazon Inspector
   - Label: "Inspector\nVulnerability Scanning"
   - Color: Orange (#FF9900)

#### Layer 2: Event Processing (Middle-Top)
1. **EventBridge**
   - AWS19 → Application Integration → Amazon EventBridge
   - Label: "EventBridge\nEvent Rules"
   - Color: Purple (#8B46FF)
   - Draw arrows DOWN from all three detection services to EventBridge

#### Layer 3: Orchestration (Middle)
1. **Lambda Function**
   - AWS19 → Compute → AWS Lambda
   - Label: "Lambda\nCredential Remediation"
   - Color: Orange (#FF9900)

2. **Step Functions**
   - AWS19 → Application Integration → AWS Step Functions
   - Label: "Step Functions\nApproval Workflow"
   - Color: Pink (#E34F45)

3. Draw arrows from EventBridge to both Lambda and Step Functions

#### Layer 4: Target Resources (Middle-Bottom)
Create a container box labeled "Target Resources":

1. **IAM**
   - AWS19 → Security → AWS IAM
   - Label: "IAM Users/Keys"

2. **S3**
   - AWS19 → Storage → Amazon S3
   - Label: "S3 Buckets"

3. **Security Groups**
   - AWS19 → Networking → Security Group
   - Label: "Security Groups"

4. **Secrets Manager**
   - AWS19 → Security → AWS Secrets Manager
   - Label: "Secrets Manager\nIncident Records"

5. Draw arrows from Lambda and Step Functions to this container

#### Layer 5: Notifications (Right Side)
1. **SNS Topic**
   - AWS19 → Application Integration → Amazon SNS
   - Label: "SNS Topic\nSecurity Alerts"
   - Color: Pink (#E34F45)

2. Add text boxes below SNS:
   - "→ Email"
   - "→ Slack"

3. Draw arrow from Lambda to SNS

#### Layer 6: Audit & Logging (Bottom)
1. **CloudTrail**
   - AWS19 → Management & Governance → AWS CloudTrail
   - Label: "CloudTrail\nAPI Audit Logs"

2. **CloudWatch Logs**
   - AWS19 → Management & Governance → Amazon CloudWatch
   - Label: "CloudWatch Logs\nLambda Execution"

3. Draw dotted lines from all components to these audit services

### Step 4: Add Visual Enhancements

1. **Container Box**: Draw a large rectangle around everything
   - Label: "AWS Account - Security Remediation Platform"
   - Border: Dashed, AWS Orange (#FF9900)

2. **Section Labels**: Add text boxes for each layer:
   - "Detection Layer" (top)
   - "Event Processing" (middle-top)
   - "Orchestration" (middle)
   - "Target Resources" (middle-bottom)
   - "Notifications" (right)
   - "Audit & Logging" (bottom)

3. **Arrow Styles**:
   - Solid arrows: Data flow
   - Dashed arrows: Logging/audit
   - Arrow labels: Add text like "Findings", "Events", "Remediate", "Notify"

### Step 5: Add Traffic Flow Annotations

Add numbered circles (1-7) to show traffic flow:

1. "GuardDuty detects threat"
2. "EventBridge receives finding"
3. "Lambda invoked"
4. "Remediation executed"
5. "Incident logged"
6. "Notification sent"
7. "Audit trail recorded"

### Step 6: Color Coding

Use consistent AWS colors:
- **Compute (Lambda)**: Orange (#FF9900)
- **Security (GuardDuty, IAM)**: Orange (#FF9900)
- **Integration (EventBridge, SNS, Step Functions)**: Pink/Purple (#E34F45)
- **Storage (S3, Secrets Manager)**: Green (#146EB4)
- **Management (CloudTrail, CloudWatch)**: Pink (#E34F45)

### Step 7: Export

1. File → Export as → PNG
2. Resolution: 300 DPI
3. Transparent Background: Unchecked (use white)
4. Border Width: 10px
5. Save as: `security-remediation-architecture.png`

---

## Alternative: Simple Diagram (5 Minutes)

If you want a quick diagram without draw.io:

### Use Mermaid Markdown

Add this to your README.md:

```markdown
## Architecture

graph TD
    A[GuardDuty] -->|Finding| B[EventBridge]
    C[AWS Config] -->|Violation| B
    B -->|Invoke| D[Lambda Function]
    B -->|Invoke| E[Step Functions]
    D -->|Remediate| F[IAM Users]
    D -->|Remediate| G[S3 Buckets]
    D -->|Log| H[Secrets Manager]
    D -->|Notify| I[SNS Topic]
    E -->|Approve| D
    I -->|Email| J[Security Team]
    I -->|Slack| K[Slack Channel]
    D -.->|Audit| L[CloudTrail]
    D -.->|Logs| M[CloudWatch]
    
    style A fill:#FF9900
    style B fill:#E34F45
    style D fill:#FF9900
    style E fill:#E34F45
    style I fill:#E34F45
```

GitHub will automatically render this as a diagram!

---

## Diagram Checklist

- [ ] All AWS services use official AWS icons
- [ ] Clear arrows showing data flow
- [ ] Labels on all arrows (e.g., "Findings", "Remediate")
- [ ] Color-coded by AWS service category
- [ ] Traffic flow annotations (numbered steps)
- [ ] Container box showing AWS account boundary
- [ ] Section labels for each layer
- [ ] High resolution (300 DPI) for presentations
- [ ] Saved as PNG and embedded in README
- [ ] Alternative: Mermaid diagram in markdown

---

## Where to Use This Diagram

1. **GitHub README**: Embed at the top of README.md
2. **LinkedIn Post**: Include when announcing project
3. **Resume**: Small version next to project description (optional)
4. **Interview Presentations**: Full-screen during technical discussions
5. **Loom Video**: Show as first slide in walkthrough

---

## Tips for Interviews

When presenting the diagram:

1. **Start with the problem**: "Manual incident response takes 2-4 hours"
2. **Show the flow**: Walk through traffic path left-to-right or top-to-bottom
3. **Highlight decisions**: "I chose Lambda over EC2 for serverless, pay-per-use"
4. **Discuss alternatives**: "I considered Step Functions for all remediation but chose Lambda for simpler cases"
5. **Connect to business**: "This 99% MTTR reduction saves security team 40 hours/month"

---

**Once you create the diagram, add it to your GitHub README and share the link with me to review!**
