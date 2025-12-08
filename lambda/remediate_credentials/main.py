"""
Automated Security Remediation - Credential Compromise Handler

This Lambda function automatically remediates compromised IAM credentials detected by GuardDuty.

Remediation Actions:
1. UnauthorizedAccess:IAMUser - Disable IAM user access keys, attach deny policy
2. Stealth:IAMUser - Similar to unauthorized access
3. PenTest:IAMUser/AdminEnable - Disable access, alert security team

Author: Jha'Mel Thorne
"""

import json
import os
import boto3
from datetime import datetime
from typing import Dict, List, Any
import traceback
import urllib3

# Initialize AWS clients
iam_client = boto3.client('iam')
sns_client = boto3.client('sns')
secretsmanager_client = boto3.client('secretsmanager')

# Environment variables
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')
SLACK_WEBHOOK_URL = os.environ.get('SLACK_WEBHOOK_URL', '')
AUTO_REMEDIATE_HIGH = os.environ.get('AUTO_REMEDIATE_HIGH', 'True').lower() == 'true'
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')
PROJECT_NAME = os.environ.get('PROJECT_NAME', 'security-remediation')

# HTTP client for Slack
http = urllib3.PoolManager()


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for GuardDuty finding remediation.
    
    Args:
        event: GuardDuty finding event from EventBridge
        context: Lambda context object
        
    Returns:
        Dict with remediation status and actions taken
    """
    print(f"Received event: {json.dumps(event, default=str)}")
    
    try:
        # Extract GuardDuty finding details
        detail = event.get('detail', {})
        finding_id = detail.get('id', 'unknown')
        finding_type = detail.get('type', 'unknown')
        severity = detail.get('severity', 0)
        title = detail.get('title', 'Unknown GuardDuty Finding')
        description = detail.get('description', 'No description available')
        
        # Extract resource information
        resource = detail.get('resource', {})
        resource_type = resource.get('resourceType', 'unknown')
        
        print(f"Processing finding: {finding_type} (Severity: {severity})")
        print(f"Resource type: {resource_type}")
        
        # Determine if automatic remediation should occur
        should_auto_remediate = determine_remediation_eligibility(
            finding_type=finding_type,
            severity=severity,
            resource_type=resource_type
        )
        
        if not should_auto_remediate:
            message = f"Finding {finding_type} does not qualify for automatic remediation"
            print(message)
            send_notification(
                severity='INFO',
                finding_type=finding_type,
                title=title,
                actions_taken=['Manual review required'],
                finding_id=finding_id
            )
            return {
                'statusCode': 200,
                'body': json.dumps({'message': message, 'remediated': False})
            }
        
        # Route to appropriate remediation handler
        actions_taken = []
        
        if 'IAMUser' in resource_type:
            actions_taken = remediate_iam_user(detail)
        elif 'AccessKey' in resource_type:
            actions_taken = remediate_access_key(detail)
        else:
            actions_taken = ['Unsupported resource type for automatic remediation']
            print(f"Unsupported resource type: {resource_type}")
        
        # Send notification with remediation results
        send_notification(
            severity=get_severity_label(severity),
            finding_type=finding_type,
            title=title,
            actions_taken=actions_taken,
            finding_id=finding_id
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Remediation completed successfully',
                'findingId': finding_id,
                'findingType': finding_type,
                'actionsTaken': actions_taken,
                'remediated': True
            }, default=str)
        }
        
    except Exception as e:
        error_message = f"Error processing GuardDuty finding: {str(e)}"
        print(error_message)
        traceback.print_exc()
        
        # Send error notification
        send_error_notification(
            error_message=error_message,
            event=event
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'remediated': False
            })
        }


def determine_remediation_eligibility(
    finding_type: str, 
    severity: float, 
    resource_type: str
) -> bool:
    """
    Determine if a finding should be automatically remediated.
    
    Args:
        finding_type: GuardDuty finding type
        severity: Numeric severity (0-10)
        resource_type: AWS resource type
        
    Returns:
        True if should auto-remediate, False otherwise
    """
    # Always remediate critical findings (severity >= 7.0)
    if severity >= 7.0:
        return True
    
    # Remediate high severity if configured
    if severity >= 4.0 and AUTO_REMEDIATE_HIGH:
        return True
    
    # Remediate specific finding types regardless of severity
    auto_remediate_types = [
        'UnauthorizedAccess:IAMUser',
        'Stealth:IAMUser',
        'CredentialAccess:IAMUser/AnomalousBehavior',
        'Policy:IAMUser/RootCredentialUsage'
    ]
    
    if any(finding_type.startswith(ft) for ft in auto_remediate_types):
        return True
    
    return False


def remediate_iam_user(detail: Dict[str, Any]) -> List[str]:
    """
    Remediate compromised IAM user by disabling access and rotating credentials.
    
    Args:
        detail: GuardDuty finding detail
        
    Returns:
        List of actions taken
    """
    actions = []
    resource = detail.get('resource', {})
    access_key_details = resource.get('accessKeyDetails', {})
    user_name = access_key_details.get('userName')
    
    if not user_name:
        # Try alternate location for username
        iam_user_details = resource.get('iamUserDetails', {})
        user_name = iam_user_details.get('userName')
    
    if not user_name:
        print("Could not determine IAM username from finding")
        return ['Unable to determine IAM username']
    
    print(f"Remediating IAM user: {user_name}")
    
    try:
        # 1. List and deactivate all access keys
        access_keys = iam_client.list_access_keys(UserName=user_name)
        for key in access_keys.get('AccessKeyMetadata', []):
            access_key_id = key['AccessKeyId']
            if key['Status'] == 'Active':
                iam_client.update_access_key(
                    UserName=user_name,
                    AccessKeyId=access_key_id,
                    Status='Inactive'
                )
                print(f"Deactivated access key: {access_key_id}")
                actions.append(f"Deactivated access key {access_key_id}")
        
        # 2. Attach explicit deny policy to prevent further access
        deny_policy_name = f'{PROJECT_NAME}-quarantine-policy'
        deny_policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Deny",
                    "Action": "*",
                    "Resource": "*",
                    "Condition": {
                        "StringEquals": {
                            "aws:RequestedRegion": "*"
                        }
                    }
                }
            ]
        }
        
        try:
            iam_client.put_user_policy(
                UserName=user_name,
                PolicyName=deny_policy_name,
                PolicyDocument=json.dumps(deny_policy_document)
            )
            print(f"Attached quarantine policy to user {user_name}")
            actions.append(f"Attached quarantine deny policy to {user_name}")
        except iam_client.exceptions.NoSuchEntityException:
            print(f"User {user_name} no longer exists")
            actions.append(f"User {user_name} was already deleted")
        
        # 3. Disable console access if present
        try:
            iam_client.delete_login_profile(UserName=user_name)
            print(f"Deleted login profile for user {user_name}")
            actions.append(f"Disabled console access for {user_name}")
        except iam_client.exceptions.NoSuchEntityException:
            print(f"No login profile found for user {user_name}")
        
        # 4. Store incident details in Secrets Manager for audit trail
        store_incident_details(
            user_name=user_name,
            finding_type=detail.get('type'),
            finding_id=detail.get('id'),
            actions_taken=actions
        )
        
        return actions
        
    except Exception as e:
        error_msg = f"Error remediating IAM user {user_name}: {str(e)}"
        print(error_msg)
        traceback.print_exc()
        return [error_msg]


def remediate_access_key(detail: Dict[str, Any]) -> List[str]:
    """
    Remediate compromised access key.
    
    Args:
        detail: GuardDuty finding detail
        
    Returns:
        List of actions taken
    """
    actions = []
    resource = detail.get('resource', {})
    access_key_details = resource.get('accessKeyDetails', {})
    
    access_key_id = access_key_details.get('accessKeyId')
    user_name = access_key_details.get('userName')
    
    if not access_key_id or not user_name:
        print("Missing access key ID or username")
        return ['Unable to determine access key details']
    
    print(f"Remediating access key: {access_key_id} for user {user_name}")
    
    try:
        # Deactivate the compromised access key
        iam_client.update_access_key(
            UserName=user_name,
            AccessKeyId=access_key_id,
            Status='Inactive'
        )
        print(f"Deactivated access key: {access_key_id}")
        actions.append(f"Deactivated compromised access key {access_key_id}")
        
        # Store incident for audit
        store_incident_details(
            user_name=user_name,
            finding_type=detail.get('type'),
            finding_id=detail.get('id'),
            actions_taken=actions,
            access_key_id=access_key_id
        )
        
        return actions
        
    except Exception as e:
        error_msg = f"Error remediating access key {access_key_id}: {str(e)}"
        print(error_msg)
        traceback.print_exc()
        return [error_msg]


def store_incident_details(
    user_name: str,
    finding_type: str,
    finding_id: str,
    actions_taken: List[str],
    access_key_id: str = None
) -> None:
    """
    Store incident details in AWS Secrets Manager for audit trail.
    
    Args:
        user_name: IAM username
        finding_type: GuardDuty finding type
        finding_id: Finding ID
        actions_taken: List of remediation actions
        access_key_id: Optional access key ID
    """
    try:
        secret_name = f'{PROJECT_NAME}/incidents/{user_name}/{finding_id}'
        incident_data = {
            'userName': user_name,
            'findingType': finding_type,
            'findingId': finding_id,
            'actionsTaken': actions_taken,
            'timestamp': datetime.utcnow().isoformat(),
            'environment': ENVIRONMENT
        }
        
        if access_key_id:
            incident_data['accessKeyId'] = access_key_id
        
        secretsmanager_client.create_secret(
            Name=secret_name,
            Description=f'Incident remediation record for {user_name}',
            SecretString=json.dumps(incident_data)
        )
        print(f"Stored incident details in Secrets Manager: {secret_name}")
        
    except secretsmanager_client.exceptions.ResourceExistsException:
        print(f"Incident record already exists for {finding_id}")
    except Exception as e:
        print(f"Failed to store incident details: {str(e)}")
        # Don't fail remediation if audit storage fails


def get_severity_label(severity: float) -> str:
    """Convert numeric severity to label."""
    if severity >= 7.0:
        return 'CRITICAL'
    elif severity >= 4.0:
        return 'HIGH'
    elif severity >= 1.0:
        return 'MEDIUM'
    else:
        return 'LOW'


def send_notification(
    severity: str,
    finding_type: str,
    title: str,
    actions_taken: List[str],
    finding_id: str
) -> None:
    """
    Send notifications via SNS and Slack.
    
    Args:
        severity: Severity label
        finding_type: Finding type
        title: Finding title
        actions_taken: List of actions
        finding_id: Finding ID
    """
    timestamp = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')
    
    # SNS message
    sns_message = f"""
Security Finding Remediated

Severity: {severity}
Finding Type: {finding_type}
Title: {title}
Finding ID: {finding_id}
Timestamp: {timestamp}

Actions Taken:
{chr(10).join(f'  • {action}' for action in actions_taken)}

Environment: {ENVIRONMENT}
Account: {boto3.client('sts').get_caller_identity()['Account']}
    """.strip()
    
    # Send SNS
    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f'[{severity}] Security Remediation: {finding_type}',
            Message=sns_message
        )
        print("SNS notification sent")
    except Exception as e:
        print(f"Failed to send SNS notification: {str(e)}")
    
    # Send Slack if configured
    if SLACK_WEBHOOK_URL:
        send_slack_notification(
            severity=severity,
            finding_type=finding_type,
            title=title,
            actions_taken=actions_taken,
            finding_id=finding_id,
            timestamp=timestamp
        )


def send_slack_notification(
    severity: str,
    finding_type: str,
    title: str,
    actions_taken: List[str],
    finding_id: str,
    timestamp: str
) -> None:
    """Send formatted notification to Slack."""
    color_map = {
        'CRITICAL': '#FF0000',
        'HIGH': '#FF6600',
        'MEDIUM': '#FFCC00',
        'LOW': '#00CC00',
        'INFO': '#0099FF'
    }
    
    slack_message = {
        'text': f'🚨 Security Finding Remediated: {severity}',
        'attachments': [
            {
                'color': color_map.get(severity, '#808080'),
                'title': title,
                'fields': [
                    {
                        'title': 'Finding Type',
                        'value': finding_type,
                        'short': True
                    },
                    {
                        'title': 'Severity',
                        'value': severity,
                        'short': True
                    },
                    {
                        'title': 'Environment',
                        'value': ENVIRONMENT,
                        'short': True
                    },
                    {
                        'title': 'Timestamp',
                        'value': timestamp,
                        'short': True
                    },
                    {
                        'title': 'Actions Taken',
                        'value': '\n'.join(f'• {action}' for action in actions_taken),
                        'short': False
                    }
                ],
                'footer': f'Finding ID: {finding_id}'
            }
        ]
    }
    
    try:
        response = http.request(
            'POST',
            SLACK_WEBHOOK_URL,
            body=json.dumps(slack_message),
            headers={'Content-Type': 'application/json'}
        )
        print(f"Slack notification sent: {response.status}")
    except Exception as e:
        print(f"Failed to send Slack notification: {str(e)}")


def send_error_notification(error_message: str, event: Dict[str, Any]) -> None:
    """Send error notification when remediation fails."""
    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject='[ERROR] Security Remediation Failed',
            Message=f"""
Security remediation encountered an error:

Error: {error_message}

Event:
{json.dumps(event, indent=2, default=str)}

Environment: {ENVIRONMENT}
            """.strip()
        )
        print("Error notification sent")
    except Exception as e:
        print(f"Failed to send error notification: {str(e)}")
