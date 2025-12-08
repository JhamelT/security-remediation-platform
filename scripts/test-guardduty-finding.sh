#!/bin/bash

# Test script for Security Remediation Platform
# This script creates test IAM users and simulates security scenarios

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Security Remediation Platform - Test Environment       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
command -v aws >/dev/null 2>&1 || { echo -e "${RED}AWS CLI not found. Please install it.${NC}"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo -e "${RED}jq not found. Please install it.${NC}"; exit 1; }

# Get AWS account info
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region || echo "us-east-1")

echo -e "${GREEN}✓ AWS Account:${NC} $ACCOUNT_ID"
echo -e "${GREEN}✓ Region:${NC} $REGION"
echo

# Function to create test IAM user
create_test_user() {
    local username=$1
    echo -e "${YELLOW}Creating test IAM user: $username${NC}"
    
    # Check if user exists
    if aws iam get-user --user-name "$username" >/dev/null 2>&1; then
        echo -e "${YELLOW}User $username already exists. Deleting existing user...${NC}"
        
        # Delete existing access keys
        aws iam list-access-keys --user-name "$username" --query 'AccessKeyMetadata[].AccessKeyId' --output text | \
        while read -r key_id; do
            aws iam delete-access-key --user-name "$username" --access-key-id "$key_id" 2>/dev/null || true
        done
        
        # Delete login profile
        aws iam delete-login-profile --user-name "$username" 2>/dev/null || true
        
        # Detach policies
        aws iam list-attached-user-policies --user-name "$username" --query 'AttachedPolicies[].PolicyArn' --output text | \
        while read -r policy_arn; do
            aws iam detach-user-policy --user-name "$username" --policy-arn "$policy_arn" 2>/dev/null || true
        done
        
        # Delete inline policies
        aws iam list-user-policies --user-name "$username" --query 'PolicyNames[]' --output text | \
        while read -r policy_name; do
            aws iam delete-user-policy --user-name "$username" --policy-name "$policy_name" 2>/dev/null || true
        done
        
        # Delete user
        aws iam delete-user --user-name "$username" 2>/dev/null || true
        sleep 2
    fi
    
    # Create new user
    aws iam create-user --user-name "$username" --tags Key=Purpose,Value=SecurityTesting Key=Environment,Value=dev
    echo -e "${GREEN}✓ User created: $username${NC}"
    
    # Create access key
    ACCESS_KEY_JSON=$(aws iam create-access-key --user-name "$username")
    ACCESS_KEY_ID=$(echo "$ACCESS_KEY_JSON" | jq -r '.AccessKey.AccessKeyId')
    SECRET_ACCESS_KEY=$(echo "$ACCESS_KEY_JSON" | jq -r '.AccessKey.SecretAccessKey')
    
    echo -e "${GREEN}✓ Access key created: $ACCESS_KEY_ID${NC}"
    echo -e "${YELLOW}  Secret: $SECRET_ACCESS_KEY${NC}"
    echo
    
    # Return values
    echo "$ACCESS_KEY_ID"
}

# Function to send test GuardDuty event to Lambda
send_test_event() {
    local lambda_name=$1
    local finding_type=$2
    local username=$3
    local access_key_id=$4
    
    echo -e "${YELLOW}Sending test GuardDuty finding to Lambda: $lambda_name${NC}"
    echo -e "${YELLOW}Finding Type: $finding_type${NC}"
    
    # Create test event
    TEST_EVENT=$(cat <<EOF
{
  "version": "0",
  "id": "test-event-$(date +%s)",
  "detail-type": "GuardDuty Finding",
  "source": "aws.guardduty",
  "account": "$ACCOUNT_ID",
  "time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "region": "$REGION",
  "detail": {
    "schemaVersion": "2.0",
    "accountId": "$ACCOUNT_ID",
    "region": "$REGION",
    "id": "test-finding-$(date +%s)",
    "type": "$finding_type",
    "title": "Test: Suspicious API activity detected",
    "description": "This is a simulated GuardDuty finding for testing automated remediation",
    "severity": 5.0,
    "createdAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "updatedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "resource": {
      "resourceType": "AccessKey",
      "accessKeyDetails": {
        "accessKeyId": "$access_key_id",
        "principalId": "test-principal",
        "userName": "$username",
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
EOF
)
    
    # Save to file
    echo "$TEST_EVENT" > /tmp/test-guardduty-event.json
    echo -e "${GREEN}✓ Test event created: /tmp/test-guardduty-event.json${NC}"
    
    # Invoke Lambda
    echo -e "${YELLOW}Invoking Lambda function...${NC}"
    RESPONSE=$(aws lambda invoke \
        --function-name "$lambda_name" \
        --payload file:///tmp/test-guardduty-event.json \
        /tmp/lambda-response.json 2>&1)
    
    echo -e "${GREEN}✓ Lambda invoked${NC}"
    echo
    echo -e "${YELLOW}Lambda Response:${NC}"
    cat /tmp/lambda-response.json | jq '.'
    echo
}

# Main test flow
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Starting Test Scenario: Compromised IAM Credentials${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo

# Create test user
TEST_USERNAME="test-compromised-user-$(date +%s)"
ACCESS_KEY_ID=$(create_test_user "$TEST_USERNAME")

# Get Lambda function name from Terraform output
echo -e "${YELLOW}Getting Lambda function name from Terraform...${NC}"
LAMBDA_NAME=$(cd terraform && terraform output -raw lambda_function_name 2>/dev/null) || LAMBDA_NAME="security-remediation-dev-credential-remediation"

if [ -z "$LAMBDA_NAME" ]; then
    echo -e "${RED}Error: Could not find Lambda function name${NC}"
    echo -e "${YELLOW}Please run 'cd terraform && terraform apply' first${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Lambda function: $LAMBDA_NAME${NC}"
echo

# Send test finding
send_test_event "$LAMBDA_NAME" "UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS" "$TEST_USERNAME" "$ACCESS_KEY_ID"

# Check remediation results
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Verifying Remediation Actions${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo

echo -e "${YELLOW}1. Checking access key status...${NC}"
KEY_STATUS=$(aws iam list-access-keys --user-name "$TEST_USERNAME" --query 'AccessKeyMetadata[0].Status' --output text 2>/dev/null || echo "N/A")
if [ "$KEY_STATUS" == "Inactive" ]; then
    echo -e "${GREEN}✓ Access key successfully deactivated${NC}"
else
    echo -e "${RED}✗ Access key status: $KEY_STATUS${NC}"
fi
echo

echo -e "${YELLOW}2. Checking for quarantine policy...${NC}"
POLICY_EXISTS=$(aws iam get-user-policy --user-name "$TEST_USERNAME" --policy-name "security-remediation-quarantine-policy" 2>/dev/null && echo "yes" || echo "no")
if [ "$POLICY_EXISTS" == "yes" ]; then
    echo -e "${GREEN}✓ Quarantine policy successfully attached${NC}"
else
    echo -e "${RED}✗ Quarantine policy not found${NC}"
fi
echo

echo -e "${YELLOW}3. Checking Lambda logs...${NC}"
LOG_GROUP="/aws/lambda/$LAMBDA_NAME"
echo -e "${YELLOW}Recent log events:${NC}"
aws logs tail "$LOG_GROUP" --since 5m --format short 2>/dev/null || echo -e "${YELLOW}No recent logs found${NC}"
echo

# Cleanup prompt
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Test Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo
echo -e "${YELLOW}Test user created: $TEST_USERNAME${NC}"
echo -e "${YELLOW}Access key: $ACCESS_KEY_ID${NC}"
echo
echo -e "${YELLOW}To clean up test resources, run:${NC}"
echo -e "  aws iam delete-access-key --user-name $TEST_USERNAME --access-key-id $ACCESS_KEY_ID"
echo -e "  aws iam delete-user-policy --user-name $TEST_USERNAME --policy-name security-remediation-quarantine-policy"
echo -e "  aws iam delete-user --user-name $TEST_USERNAME"
echo
echo -e "${YELLOW}Or run:${NC}"
echo -e "  ./scripts/cleanup-test-users.sh"
echo
