"""
S3 Bucket Remediation Lambda Function

Automatically remediates S3 bucket security violations by:
- Blocking public access at bucket level
- Removing public ACLs
- Deleting overly permissive bucket policies
- Publishing remediation results to SNS
"""

import json
import os
import boto3
from datetime import datetime
from typing import Dict, Any

# AWS clients
s3_client = boto3.client('s3')
sns_client = boto3.client('sns')

# Environment variables
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'prod')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for S3 bucket remediation.
    
    Args:
        event: EventBridge event containing AWS Config compliance change
        context: Lambda context object
        
    Returns:
        Dict with remediation status and details
    """
    print(f"Received event: {json.dumps(event)}")
    
    try:
        # Extract Config rule details
        detail = event.get('detail', {})
        config_rule_name = detail.get('configRuleName', 'Unknown')
        resource_id = detail.get('resourceId', '')
        resource_type = detail.get('resourceType', '')
        compliance_type = detail.get('newEvaluationResult', {}).get('complianceType', '')
        
        print(f"Processing Config violation: {config_rule_name}")
        print(f"Resource: {resource_id} | Type: {resource_type} | Compliance: {compliance_type}")
        
        # Extract bucket name from resource ID (format: AWS::S3::Bucket/bucket-name)
        if resource_type == 'AWS::S3::Bucket' and '/' in resource_id:
            bucket_name = resource_id.split('/')[-1]
        else:
            bucket_name = resource_id
        
        # Remediate based on Config rule
        if 's3-bucket-public-read-prohibited' in config_rule_name or \
           's3-bucket-public-write-prohibited' in config_rule_name:
            remediation_result = remediate_public_s3_bucket(bucket_name)
        else:
            remediation_result = {
                'action': 'no_automatic_remediation',
                'reason': f'No automated remediation for rule: {config_rule_name}',
                'actions': []
            }
        
        # Publish remediation result to SNS
        publish_remediation_result(
            config_rule_name=config_rule_name,
            bucket_name=bucket_name,
            compliance_type=compliance_type,
            remediation_result=remediation_result
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'S3 remediation completed successfully',
                'bucket_name': bucket_name,
                'config_rule': config_rule_name,
                'remediation_actions': remediation_result.get('actions', [])
            })
        }
        
    except Exception as e:
        error_message = f"Error processing S3 remediation: {str(e)}"
        print(error_message)
        
        # Publish error to SNS
        publish_error(event, error_message)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'S3 remediation failed',
                'error': str(e)
            })
        }


def remediate_public_s3_bucket(bucket_name: str) -> Dict[str, Any]:
    """
    Remediate public S3 bucket by:
    1. Enabling Block Public Access settings
    2. Removing public ACLs
    3. Removing overly permissive bucket policies
    """
    actions_taken = []
    
    try:
        print(f"Remediating S3 bucket: {bucket_name}")
        
        # 1. Enable Block Public Access settings
        try:
            s3_client.put_public_access_block(
                Bucket=bucket_name,
                PublicAccessBlockConfiguration={
                    'BlockPublicAcls': True,
                    'IgnorePublicAcls': True,
                    'BlockPublicPolicy': True,
                    'RestrictPublicBuckets': True
                }
            )
            actions_taken.append("Enabled Block Public Access for all settings")
            print(f"Enabled Block Public Access for bucket: {bucket_name}")
        except Exception as e:
            error_msg = f"Error enabling Block Public Access: {str(e)}"
            actions_taken.append(error_msg)
            print(error_msg)
        
        # 2. Remove public ACLs by setting private ACL
        try:
            s3_client.put_bucket_acl(
                Bucket=bucket_name,
                ACL='private'
            )
            actions_taken.append("Set bucket ACL to private")
            print(f"Set bucket ACL to private for: {bucket_name}")
        except Exception as e:
            error_msg = f"Error setting bucket ACL: {str(e)}"
            actions_taken.append(error_msg)
            print(error_msg)
        
        # 3. Check and remove overly permissive bucket policy
        try:
            # Get current bucket policy
            try:
                policy_response = s3_client.get_bucket_policy(Bucket=bucket_name)
                policy = json.loads(policy_response['Policy'])
                
                # Check if policy has public statements
                has_public_policy = False
                for statement in policy.get('Statement', []):
                    principal = statement.get('Principal', {})
                    if principal == '*' or principal == {'AWS': '*'}:
                        has_public_policy = True
                        break
                
                if has_public_policy:
                    # Delete the overly permissive policy
                    s3_client.delete_bucket_policy(Bucket=bucket_name)
                    actions_taken.append("Deleted overly permissive bucket policy")
                    print(f"Deleted public bucket policy for: {bucket_name}")
                else:
                    actions_taken.append("Bucket policy does not grant public access")
                    
            except s3_client.exceptions.NoSuchBucketPolicy:
                actions_taken.append("No bucket policy exists")
                
        except Exception as e:
            error_msg = f"Error checking/removing bucket policy: {str(e)}"
            actions_taken.append(error_msg)
            print(error_msg)
        
        # 4. Verify remediation by checking current Block Public Access status
        try:
            response = s3_client.get_public_access_block(Bucket=bucket_name)
            config = response['PublicAccessBlockConfiguration']
            
            if all([
                config.get('BlockPublicAcls'),
                config.get('IgnorePublicAcls'),
                config.get('BlockPublicPolicy'),
                config.get('RestrictPublicBuckets')
            ]):
                actions_taken.append("✅ Verified: All Block Public Access settings enabled")
                print(f"Verification successful for bucket: {bucket_name}")
            else:
                actions_taken.append("⚠️ Warning: Some Block Public Access settings not enabled")
                
        except Exception as e:
            error_msg = f"Error verifying remediation: {str(e)}"
            actions_taken.append(error_msg)
            print(error_msg)
        
        return {
            'action': 's3_public_access_remediation',
            'bucket_name': bucket_name,
            'actions': actions_taken,
            'status': 'success',
            'timestamp': datetime.now().isoformat()
        }
        
    except Exception as e:
        return {
            'action': 's3_public_access_remediation',
            'bucket_name': bucket_name,
            'status': 'failed',
            'error': str(e),
            'actions': actions_taken,
            'timestamp': datetime.now().isoformat()
        }


def publish_remediation_result(config_rule_name: str, bucket_name: str, 
                               compliance_type: str, remediation_result: Dict[str, Any]) -> None:
    """Publish remediation result to SNS topic."""
    
    message = {
        'alert_type': 'S3 Config Remediation Complete',
        'config_rule': config_rule_name,
        'bucket_name': bucket_name,
        'compliance_type': compliance_type,
        'timestamp': datetime.now().isoformat(),
        'remediation_action': remediation_result.get('action'),
        'actions_taken': remediation_result.get('actions', []),
        'status': remediation_result.get('status', 'completed')
    }
    
    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"🔒 S3 Remediation: {bucket_name}",
            Message=json.dumps(message, indent=2)
        )
        print(f"Published remediation result to SNS: {SNS_TOPIC_ARN}")
    except Exception as e:
        print(f"Error publishing to SNS: {str(e)}")


def publish_error(event: Dict[str, Any], error_message: str) -> None:
    """Publish error notification to SNS."""
    
    message = {
        'alert_type': 'S3 Remediation Error',
        'error': error_message,
        'event': event,
        'timestamp': datetime.now().isoformat()
    }
    
    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject="❌ S3 Remediation Error",
            Message=json.dumps(message, indent=2)
        )
    except Exception as e:
        print(f"Error publishing error to SNS: {str(e)}")
