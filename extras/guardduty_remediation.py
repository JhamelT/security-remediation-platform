"""
GuardDuty Remediation Lambda Function

Automatically remediates GuardDuty security findings by:
- Disabling compromised IAM users
- Rotating credentials via Secrets Manager
- Isolating compromised EC2 instances
- Publishing remediation results to SNS
"""

import json
import os
import boto3
from datetime import datetime
from typing import Dict, Any

# AWS clients
iam_client = boto3.client('iam')
secrets_client = boto3.client('secretsmanager')
ec2_client = boto3.client('ec2')
sns_client = boto3.client('sns')

# Environment variables
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'prod')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for GuardDuty findings remediation.
    
    Args:
        event: EventBridge event containing GuardDuty finding
        context: Lambda context object
        
    Returns:
        Dict with remediation status and details
    """
    print(f"Received event: {json.dumps(event)}")
    
    try:
        # Extract GuardDuty finding details
        detail = event.get('detail', {})
        finding_type = detail.get('type', 'Unknown')
        severity = detail.get('severity', 0)
        account_id = detail.get('accountId', '')
        region = detail.get('region', '')
        resource = detail.get('resource', {})
        
        print(f"Processing finding: {finding_type} | Severity: {severity}")
        
        # Route to appropriate remediation based on finding type
        remediation_result = route_remediation(finding_type, detail, resource)
        
        # Publish remediation result to SNS
        publish_remediation_result(
            finding_type=finding_type,
            severity=severity,
            account_id=account_id,
            region=region,
            remediation_result=remediation_result
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Remediation completed successfully',
                'finding_type': finding_type,
                'remediation_actions': remediation_result.get('actions', [])
            })
        }
        
    except Exception as e:
        error_message = f"Error processing GuardDuty finding: {str(e)}"
        print(error_message)
        
        # Publish error to SNS
        publish_error(event, error_message)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Remediation failed',
                'error': str(e)
            })
        }


def route_remediation(finding_type: str, detail: Dict[str, Any], resource: Dict[str, Any]) -> Dict[str, Any]:
    """Route finding to appropriate remediation function."""
    
    # IAM credential compromise findings
    if 'CredentialAccess' in finding_type or 'UnauthorizedAccess:IAMUser' in finding_type:
        return remediate_iam_credential_compromise(detail, resource)
    
    # EC2 instance compromise findings
    elif 'UnauthorizedAccess:EC2' in finding_type or 'Backdoor:EC2' in finding_type:
        return remediate_ec2_compromise(detail, resource)
    
    # CloudTrail logging disabled
    elif 'CloudTrailLoggingDisabled' in finding_type:
        return remediate_cloudtrail_disabled(detail, resource)
    
    # Root credential usage
    elif 'RootCredentialUsage' in finding_type:
        return remediate_root_credential_usage(detail, resource)
    
    else:
        return {
            'action': 'no_automatic_remediation',
            'reason': f'No automated remediation defined for {finding_type}',
            'actions': []
        }


def remediate_iam_credential_compromise(detail: Dict[str, Any], resource: Dict[str, Any]) -> Dict[str, Any]:
    """
    Remediate compromised IAM credentials by:
    1. Disabling all access keys
    2. Attaching explicit deny policy
    3. Rotating credentials in Secrets Manager (if applicable)
    """
    actions_taken = []
    
    try:
        # Extract IAM user information
        access_key_details = resource.get('accessKeyDetails', {})
        username = access_key_details.get('userName')
        access_key_id = access_key_details.get('accessKeyId')
        
        if not username:
            return {
                'action': 'skipped',
                'reason': 'No IAM username found in finding',
                'actions': []
            }
        
        print(f"Remediating IAM user: {username}")
        
        # 1. List and disable all access keys for this user
        try:
            response = iam_client.list_access_keys(UserName=username)
            for key in response.get('AccessKeyMetadata', []):
                key_id = key['AccessKeyId']
                if key['Status'] == 'Active':
                    iam_client.update_access_key(
                        UserName=username,
                        AccessKeyId=key_id,
                        Status='Inactive'
                    )
                    actions_taken.append(f"Disabled access key: {key_id}")
                    print(f"Disabled access key: {key_id}")
        except Exception as e:
            actions_taken.append(f"Error disabling access keys: {str(e)}")
        
        # 2. Attach explicit deny policy to prevent any actions
        deny_policy_name = f"SecurityAutomation-DenyAll-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        deny_policy = {
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
                UserName=username,
                PolicyName=deny_policy_name,
                PolicyDocument=json.dumps(deny_policy)
            )
            actions_taken.append(f"Attached deny-all policy: {deny_policy_name}")
            print(f"Attached deny-all policy to user: {username}")
        except Exception as e:
            actions_taken.append(f"Error attaching deny policy: {str(e)}")
        
        # 3. Attempt to rotate credentials in Secrets Manager (if secret exists)
        try:
            # Try to find secret with this username
            secret_name = f"iam-credentials/{username}"
            try:
                secrets_client.describe_secret(SecretId=secret_name)
                # Secret exists, trigger rotation
                secrets_client.rotate_secret(SecretId=secret_name)
                actions_taken.append(f"Triggered credential rotation in Secrets Manager: {secret_name}")
                print(f"Triggered rotation for secret: {secret_name}")
            except secrets_client.exceptions.ResourceNotFoundException:
                # Secret doesn't exist, skip rotation
                actions_taken.append("No Secrets Manager secret found for rotation")
        except Exception as e:
            actions_taken.append(f"Error checking Secrets Manager: {str(e)}")
        
        return {
            'action': 'iam_credential_remediation',
            'username': username,
            'access_key_id': access_key_id,
            'actions': actions_taken,
            'status': 'success'
        }
        
    except Exception as e:
        return {
            'action': 'iam_credential_remediation',
            'status': 'failed',
            'error': str(e),
            'actions': actions_taken
        }


def remediate_ec2_compromise(detail: Dict[str, Any], resource: Dict[str, Any]) -> Dict[str, Any]:
    """
    Remediate compromised EC2 instance by isolating it in a quarantine security group.
    """
    actions_taken = []
    
    try:
        # Extract instance details
        instance_details = resource.get('instanceDetails', {})
        instance_id = instance_details.get('instanceId')
        
        if not instance_id:
            return {
                'action': 'skipped',
                'reason': 'No instance ID found in finding',
                'actions': []
            }
        
        print(f"Remediating EC2 instance: {instance_id}")
        
        # Get current instance details
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        instance = response['Reservations'][0]['Instances'][0]
        vpc_id = instance['VpcId']
        
        # Create quarantine security group (if it doesn't exist)
        quarantine_sg_name = 'security-automation-quarantine'
        try:
            # Try to find existing quarantine SG
            sg_response = ec2_client.describe_security_groups(
                Filters=[
                    {'Name': 'group-name', 'Values': [quarantine_sg_name]},
                    {'Name': 'vpc-id', 'Values': [vpc_id]}
                ]
            )
            
            if sg_response['SecurityGroups']:
                quarantine_sg_id = sg_response['SecurityGroups'][0]['GroupId']
                actions_taken.append(f"Using existing quarantine security group: {quarantine_sg_id}")
            else:
                # Create new quarantine SG (denies all inbound/outbound)
                sg_create = ec2_client.create_security_group(
                    GroupName=quarantine_sg_name,
                    Description='Quarantine security group for compromised instances',
                    VpcId=vpc_id
                )
                quarantine_sg_id = sg_create['GroupId']
                
                # Remove default outbound rule
                ec2_client.revoke_security_group_egress(
                    GroupId=quarantine_sg_id,
                    IpPermissions=[{
                        'IpProtocol': '-1',
                        'IpRanges': [{'CidrIp': '0.0.0.0/0'}]
                    }]
                )
                
                actions_taken.append(f"Created quarantine security group: {quarantine_sg_id}")
                
        except Exception as e:
            actions_taken.append(f"Error managing quarantine security group: {str(e)}")
            raise
        
        # Modify instance to use quarantine security group
        ec2_client.modify_instance_attribute(
            InstanceId=instance_id,
            Groups=[quarantine_sg_id]
        )
        actions_taken.append(f"Isolated instance {instance_id} in quarantine security group")
        
        # Tag instance as compromised
        ec2_client.create_tags(
            Resources=[instance_id],
            Tags=[
                {'Key': 'SecurityStatus', 'Value': 'Compromised'},
                {'Key': 'QuarantinedBy', 'Value': 'SecurityAutomation'},
                {'Key': 'QuarantineDate', 'Value': datetime.now().isoformat()}
            ]
        )
        actions_taken.append(f"Tagged instance as compromised")
        
        return {
            'action': 'ec2_instance_isolation',
            'instance_id': instance_id,
            'quarantine_sg_id': quarantine_sg_id,
            'actions': actions_taken,
            'status': 'success'
        }
        
    except Exception as e:
        return {
            'action': 'ec2_instance_isolation',
            'status': 'failed',
            'error': str(e),
            'actions': actions_taken
        }


def remediate_cloudtrail_disabled(detail: Dict[str, Any], resource: Dict[str, Any]) -> Dict[str, Any]:
    """Log CloudTrail disabled finding for manual review."""
    return {
        'action': 'manual_review_required',
        'finding_type': 'CloudTrail Disabled',
        'reason': 'CloudTrail re-enablement requires manual verification',
        'actions': ['Notification sent to security team']
    }


def remediate_root_credential_usage(detail: Dict[str, Any], resource: Dict[str, Any]) -> Dict[str, Any]:
    """Log root credential usage for manual review."""
    return {
        'action': 'manual_review_required',
        'finding_type': 'Root Credential Usage',
        'reason': 'Root credential usage requires manual investigation',
        'actions': ['Notification sent to security team']
    }


def publish_remediation_result(finding_type: str, severity: float, account_id: str, 
                               region: str, remediation_result: Dict[str, Any]) -> None:
    """Publish remediation result to SNS topic."""
    
    message = {
        'alert_type': 'GuardDuty Remediation Complete',
        'finding_type': finding_type,
        'severity': severity,
        'account_id': account_id,
        'region': region,
        'timestamp': datetime.now().isoformat(),
        'remediation_action': remediation_result.get('action'),
        'actions_taken': remediation_result.get('actions', []),
        'status': remediation_result.get('status', 'completed')
    }
    
    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"🔒 GuardDuty Remediation: {finding_type}",
            Message=json.dumps(message, indent=2)
        )
        print(f"Published remediation result to SNS: {SNS_TOPIC_ARN}")
    except Exception as e:
        print(f"Error publishing to SNS: {str(e)}")


def publish_error(event: Dict[str, Any], error_message: str) -> None:
    """Publish error notification to SNS."""
    
    message = {
        'alert_type': 'GuardDuty Remediation Error',
        'error': error_message,
        'event': event,
        'timestamp': datetime.now().isoformat()
    }
    
    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject="❌ GuardDuty Remediation Error",
            Message=json.dumps(message, indent=2)
        )
    except Exception as e:
        print(f"Error publishing error to SNS: {str(e)}")
