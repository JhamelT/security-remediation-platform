#!/bin/bash

# Cleanup script for test resources created by security remediation testing

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Security Remediation Platform - Cleanup Test Resources ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo

# Find all test users
echo -e "${YELLOW}Finding test users...${NC}"
TEST_USERS=$(aws iam list-users --query 'Users[?starts_with(UserName, `test-compromised-user`)].UserName' --output text)

if [ -z "$TEST_USERS" ]; then
    echo -e "${GREEN}✓ No test users found${NC}"
    exit 0
fi

echo -e "${YELLOW}Found test users:${NC}"
echo "$TEST_USERS"
echo

# Clean up each user
for username in $TEST_USERS; do
    echo -e "${YELLOW}Cleaning up user: $username${NC}"
    
    # Delete access keys
    echo "  - Deleting access keys..."
    aws iam list-access-keys --user-name "$username" --query 'AccessKeyMetadata[].AccessKeyId' --output text | \
    while read -r key_id; do
        aws iam delete-access-key --user-name "$username" --access-key-id "$key_id" 2>/dev/null || true
        echo "    ✓ Deleted key: $key_id"
    done
    
    # Delete login profile
    echo "  - Deleting login profile..."
    aws iam delete-login-profile --user-name "$username" 2>/dev/null && echo "    ✓ Login profile deleted" || echo "    - No login profile"
    
    # Detach managed policies
    echo "  - Detaching managed policies..."
    aws iam list-attached-user-policies --user-name "$username" --query 'AttachedPolicies[].PolicyArn' --output text | \
    while read -r policy_arn; do
        aws iam detach-user-policy --user-name "$username" --policy-arn "$policy_arn" 2>/dev/null || true
        echo "    ✓ Detached: $policy_arn"
    done
    
    # Delete inline policies
    echo "  - Deleting inline policies..."
    aws iam list-user-policies --user-name "$username" --query 'PolicyNames[]' --output text | \
    while read -r policy_name; do
        aws iam delete-user-policy --user-name "$username" --policy-name "$policy_name" 2>/dev/null || true
        echo "    ✓ Deleted policy: $policy_name"
    done
    
    # Remove from groups
    echo "  - Removing from groups..."
    aws iam list-groups-for-user --user-name "$username" --query 'Groups[].GroupName' --output text | \
    while read -r group_name; do
        aws iam remove-user-from-group --user-name "$username" --group-name "$group_name" 2>/dev/null || true
        echo "    ✓ Removed from group: $group_name"
    done
    
    # Delete user
    echo "  - Deleting user..."
    aws iam delete-user --user-name "$username"
    echo -e "${GREEN}  ✓ User deleted: $username${NC}"
    echo
done

# Clean up Secrets Manager incident records
echo -e "${YELLOW}Cleaning up Secrets Manager incident records...${NC}"
SECRETS=$(aws secretsmanager list-secrets --query 'SecretList[?starts_with(Name, `security-remediation/incidents/test-compromised-user`)].Name' --output text)

if [ -n "$SECRETS" ]; then
    for secret_name in $SECRETS; do
        aws secretsmanager delete-secret --secret-id "$secret_name" --force-delete-without-recovery 2>/dev/null && \
        echo "  ✓ Deleted secret: $secret_name" || true
    done
else
    echo "  - No incident records found"
fi
echo

echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
