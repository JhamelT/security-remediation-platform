#!/bin/bash
#
# AWS Security Automation Platform - Quick Start Script
# This script automates the deployment process
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install it first."
        exit 1
    fi
    print_success "AWS CLI installed"
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform not found. Please install it first."
        exit 1
    fi
    print_success "Terraform installed ($(terraform version | head -n1))"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    print_success "AWS credentials configured (Account: $ACCOUNT_ID, Region: $AWS_REGION)"
}

# Configure Terraform variables
configure_terraform() {
    print_header "Configuring Terraform Variables"
    
    cd terraform
    
    if [ ! -f terraform.tfvars ]; then
        print_info "Creating terraform.tfvars from template..."
        cp terraform.tfvars.example terraform.tfvars
        
        echo ""
        print_warning "Please edit terraform/terraform.tfvars with your values:"
        echo "  • slack_webhook_url   (required if using Slack)"
        echo "  • notification_email  (required)"
        echo ""
        read -p "Press Enter to open terraform.tfvars in your editor..."
        ${EDITOR:-nano} terraform.tfvars
    else
        print_info "terraform.tfvars already exists"
        read -p "Do you want to edit it? (y/n): " edit_vars
        if [[ "$edit_vars" == "y" ]]; then
            ${EDITOR:-nano} terraform.tfvars
        fi
    fi
    
    cd ..
}

# Initialize Terraform
init_terraform() {
    print_header "Initializing Terraform"
    
    cd terraform
    terraform init
    print_success "Terraform initialized"
    cd ..
}

# Plan Terraform deployment
plan_terraform() {
    print_header "Planning Terraform Deployment"
    
    cd terraform
    terraform plan -out=tfplan
    
    echo ""
    print_warning "Review the plan above carefully."
    read -p "Do you want to proceed with deployment? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        print_error "Deployment cancelled by user"
        rm -f tfplan
        exit 0
    fi
    
    cd ..
}

# Apply Terraform deployment
apply_terraform() {
    print_header "Deploying Infrastructure"
    
    cd terraform
    terraform apply tfplan
    rm -f tfplan
    
    print_success "Infrastructure deployed successfully!"
    echo ""
    
    # Get outputs
    print_info "Deployment Outputs:"
    terraform output
    
    cd ..
}

# Post-deployment verification
verify_deployment() {
    print_header "Verifying Deployment"
    
    # Check GuardDuty
    print_info "Checking GuardDuty detector..."
    if aws guardduty list-detectors --query 'DetectorIds[0]' --output text &> /dev/null; then
        DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
        print_success "GuardDuty detector enabled: $DETECTOR_ID"
    else
        print_warning "GuardDuty detector not found (may be disabled in tfvars)"
    fi
    
    # Check EventBridge rules
    print_info "Checking EventBridge rules..."
    RULES_COUNT=$(aws events list-rules --name-prefix security-automation --query 'length(Rules)' --output text)
    if [ "$RULES_COUNT" -gt 0 ]; then
        print_success "EventBridge rules created: $RULES_COUNT rules"
    else
        print_error "No EventBridge rules found"
    fi
    
    # Check Lambda functions
    print_info "Checking Lambda functions..."
    LAMBDA_COUNT=$(aws lambda list-functions --query 'length(Functions[?contains(FunctionName, `security`)])' --output text)
    if [ "$LAMBDA_COUNT" -gt 0 ]; then
        print_success "Lambda functions deployed: $LAMBDA_COUNT functions"
    else
        print_error "No Lambda functions found"
    fi
    
    # Check SNS topic
    print_info "Checking SNS topic..."
    if aws sns list-topics --query 'Topics[?contains(TopicArn, `security`)]' --output text &> /dev/null; then
        print_success "SNS topic created"
    else
        print_error "SNS topic not found"
    fi
}

# Provide next steps
show_next_steps() {
    print_header "Next Steps"
    
    echo ""
    print_info "1. Confirm Email Subscription"
    echo "   • Check your email inbox for 'AWS Notification - Subscription Confirmation'"
    echo "   • Click 'Confirm subscription' link"
    echo ""
    
    print_info "2. Test the Platform"
    echo "   • Create a test S3 bucket and make it public"
    echo "   • Watch CloudWatch logs: aws logs tail /aws/lambda/security-remediation-s3 --follow"
    echo ""
    
    print_info "3. Monitor Security Events"
    echo "   • GuardDuty findings: https://console.aws.amazon.com/guardduty/"
    echo "   • Lambda logs: https://console.aws.amazon.com/cloudwatch/logs"
    echo "   • Slack channel: Check #security-alerts"
    echo ""
    
    print_info "4. Documentation"
    echo "   • Deployment guide: DEPLOYMENT.md"
    echo "   • Architecture: docs/ARCHITECTURE.md"
    echo "   • Testing: docs/TESTING.md"
    echo ""
    
    print_success "Security Automation Platform deployed successfully! 🎉"
}

# Main execution
main() {
    clear
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║   AWS Security Automation Platform - Quick Start     ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    check_prerequisites
    configure_terraform
    init_terraform
    plan_terraform
    apply_terraform
    verify_deployment
    show_next_steps
}

# Run main function
main
