"""
Slack Notifier Lambda Function

Receives SNS notifications and formats them as rich Slack messages
with color coding based on severity.
"""

import json
import os
import boto3
import urllib3
from datetime import datetime
from typing import Dict, Any

# AWS clients
secrets_client = boto3.client('secretsmanager')

# HTTP client
http = urllib3.PoolManager()

# Environment variables
SLACK_WEBHOOK_SECRET_NAME = os.environ['SLACK_WEBHOOK_SECRET_NAME']
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'prod')

# Cache for Slack webhook URL
slack_webhook_url_cache = None


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for Slack notifications.
    
    Args:
        event: SNS event containing security notification
        context: Lambda context object
        
    Returns:
        Dict with notification status
    """
    print(f"Received event: {json.dumps(event)}")
    
    try:
        # Get Slack webhook URL from Secrets Manager
        slack_webhook_url = get_slack_webhook_url()
        
        # Parse SNS message
        for record in event.get('Records', []):
            sns_message = json.loads(record['Sns']['Message'])
            sns_subject = record['Sns'].get('Subject', 'Security Alert')
            
            # Format message for Slack
            slack_payload = format_slack_message(sns_subject, sns_message)
            
            # Send to Slack
            send_to_slack(slack_webhook_url, slack_payload)
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Notification sent to Slack successfully'})
        }
        
    except Exception as e:
        error_message = f"Error sending Slack notification: {str(e)}"
        print(error_message)
        return {
            'statusCode': 500,
            'body': json.dumps({'message': 'Failed to send Slack notification', 'error': str(e)})
        }


def get_slack_webhook_url() -> str:
    """Retrieve Slack webhook URL from Secrets Manager with caching."""
    global slack_webhook_url_cache
    
    if slack_webhook_url_cache:
        return slack_webhook_url_cache
    
    try:
        response = secrets_client.get_secret_value(SecretId=SLACK_WEBHOOK_SECRET_NAME)
        secret = json.loads(response['SecretString'])
        slack_webhook_url_cache = secret['webhook_url']
        return slack_webhook_url_cache
    except Exception as e:
        print(f"Error retrieving Slack webhook from Secrets Manager: {str(e)}")
        raise


def format_slack_message(subject: str, message: Dict[str, Any]) -> Dict[str, Any]:
    """
    Format security notification as rich Slack message with blocks and attachments.
    """
    alert_type = message.get('alert_type', 'Security Alert')
    
    # Determine color based on alert type or severity
    color = get_alert_color(message)
    
    # Build Slack blocks
    blocks = [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": f"🚨 {alert_type}",
                "emoji": True
            }
        },
        {
            "type": "section",
            "fields": build_message_fields(message)
        }
    ]
    
    # Add actions section if remediation was performed
    if message.get('actions_taken'):
        blocks.append({
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*Actions Taken:*\n" + "\n".join([f"• {action}" for action in message['actions_taken']])
            }
        })
    
    # Add divider
    blocks.append({"type": "divider"})
    
    # Build Slack payload
    slack_payload = {
        "text": subject,  # Fallback text
        "blocks": blocks,
        "attachments": [
            {
                "color": color,
                "footer": f"Security Automation Platform | {ENVIRONMENT.upper()}",
                "ts": int(datetime.now().timestamp())
            }
        ]
    }
    
    return slack_payload


def get_alert_color(message: Dict[str, Any]) -> str:
    """Determine Slack attachment color based on severity or alert type."""
    
    alert_type = message.get('alert_type', '').lower()
    severity = message.get('severity', 0)
    status = message.get('status', '').lower()
    
    # Error status
    if 'error' in alert_type or status == 'failed':
        return "danger"  # Red
    
    # Critical/High severity
    if severity >= 7.0 or 'critical' in alert_type:
        return "danger"  # Red
    elif severity >= 4.0 or 'high' in alert_type:
        return "warning"  # Orange
    
    # Success/Remediation complete
    if 'complete' in alert_type or status == 'success':
        return "good"  # Green
    
    # Default
    return "#36a64f"  # Blue-green


def build_message_fields(message: Dict[str, Any]) -> list:
    """Build Slack message fields from notification data."""
    
    fields = []
    
    # Map of message keys to Slack field labels
    field_mapping = {
        'finding_type': 'Finding Type',
        'config_rule': 'Config Rule',
        'severity': 'Severity',
        'account_id': 'AWS Account',
        'region': 'Region',
        'bucket_name': 'Bucket Name',
        'username': 'IAM User',
        'instance_id': 'Instance ID',
        'compliance_type': 'Compliance Status',
        'remediation_action': 'Remediation',
        'status': 'Status',
        'timestamp': 'Timestamp'
    }
    
    for key, label in field_mapping.items():
        if key in message:
            value = message[key]
            
            # Format severity
            if key == 'severity' and isinstance(value, (int, float)):
                if value >= 7.0:
                    value = f"{value} - CRITICAL"
                elif value >= 4.0:
                    value = f"{value} - HIGH"
                else:
                    value = f"{value} - MEDIUM"
            
            # Format status with emoji
            if key == 'status':
                if value == 'success':
                    value = "✅ Success"
                elif value == 'failed':
                    value = "❌ Failed"
            
            fields.append({
                "type": "mrkdwn",
                "text": f"*{label}:*\n{value}"
            })
    
    return fields


def send_to_slack(webhook_url: str, payload: Dict[str, Any]) -> None:
    """Send formatted message to Slack webhook."""
    
    try:
        encoded_payload = json.dumps(payload).encode('utf-8')
        
        response = http.request(
            'POST',
            webhook_url,
            body=encoded_payload,
            headers={'Content-Type': 'application/json'}
        )
        
        if response.status == 200:
            print("Message sent to Slack successfully")
        else:
            print(f"Failed to send message to Slack. Status: {response.status}, Response: {response.data}")
            
    except Exception as e:
        print(f"Error sending message to Slack: {str(e)}")
        raise
