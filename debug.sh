#!/bin/bash
# Debug script for Auto Scaling Group issues

set -e

# Configuration
ASG_NAME="proxy-lamp-asg-60111207"  # Your ASG name from the logs
REGION="eu-central-1"

echo "=== Auto Scaling Group Debug Script ==="
echo "ASG Name: $ASG_NAME"
echo "Region: $REGION"
echo ""

# 1. Check if ASG exists and get basic info
echo "1. Auto Scaling Group Overview:"
aws autoscaling describe-auto-scaling-groups \
  --region "$REGION" \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].{MinSize:MinSize,MaxSize:MaxSize,DesiredCapacity:DesiredCapacity,HealthCheckType:HealthCheckType,HealthCheckGracePeriod:HealthCheckGracePeriod}' \
  --output table

echo ""

# 2. Check all instances in ASG
echo "2. All Instances in ASG:"
INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
  --region "$REGION" \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[*].{InstanceId:InstanceId,State:LifecycleState,Health:HealthStatus,AZ:AvailabilityZone,LaunchTime:CreatedTime}' \
  --output table)

echo "$INSTANCES"

# 3. Get instance IDs for further investigation
INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
  --region "$REGION" \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
  --output text)

if [ -z "$INSTANCE_IDS" ]; then
  echo "❌ No instances found in ASG!"
  echo ""
  echo "Possible causes:"
  echo "1. Launch template issues"
  echo "2. No capacity in availability zones"
  echo "3. Service limits reached"
  echo "4. IAM permissions issues"
  echo ""
  
  # Check launch template
  LAUNCH_TEMPLATE_ID=$(aws autoscaling describe-auto-scaling-groups \
    --region "$REGION" \
    --auto-scaling-group-names "$ASG_NAME" \
    --query 'AutoScalingGroups[0].LaunchTemplate.LaunchTemplateId' \
    --output text)
  
  echo "Launch Template ID: $LAUNCH_TEMPLATE_ID"
  
  if [ "$LAUNCH_TEMPLATE_ID" != "None" ]; then
    echo "Launch Template Details:"
    aws ec2 describe-launch-templates \
      --region "$REGION" \
      --launch-template-ids "$LAUNCH_TEMPLATE_ID" \
      --query 'LaunchTemplates[0].{Name:LaunchTemplateName,LatestVersion:LatestVersionNumber,CreatedBy:CreatedBy}' \
      --output table
  fi
  
  exit 1
fi

echo ""
echo "3. Instance Details:"
for INSTANCE_ID in $INSTANCE_IDS; do
  echo "--- Instance: $INSTANCE_ID ---"
  
  # Get instance details
  aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].{State:State.Name,PublicIP:PublicIpAddress,PrivateIP:PrivateIpAddress,LaunchTime:LaunchTime,InstanceType:InstanceType}' \
    --output table
  
  # Get instance status checks
  echo "Status Checks:"
  aws ec2 describe-instance-status \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'InstanceStatuses[0].{SystemStatus:SystemStatus.Status,InstanceStatus:InstanceStatus.Status}' \
    --output table 2>/dev/null || echo "Status checks not available yet"
  
  echo ""
done

echo ""
echo "4. Checking Cloud-Init Logs (if available):"
for INSTANCE_ID in $INSTANCE_IDS; do
  echo "--- Cloud-Init logs for $INSTANCE_ID ---"
  
  # Try to get cloud-init logs from CloudWatch
  aws logs describe-log-streams \
    --region "$REGION" \
    --log-group-name "/aws/ec2/proxy-lamp/cloud-init" \
    --log-stream-name-prefix "$INSTANCE_ID" \
    --query 'logStreams[0].logStreamName' \
    --output text 2>/dev/null | while read LOG_STREAM; do
    
    if [ "$LOG_STREAM" != "None" ] && [ -n "$LOG_STREAM" ]; then
      echo "Latest cloud-init log entries:"
      aws logs get-log-events \
        --region "$REGION" \
        --log-group-name "/aws/ec2/proxy-lamp/cloud-init" \
        --log-stream-name "$LOG_STREAM" \
        --limit 20 \
        --query 'events[*].message' \
        --output text 2>/dev/null || echo "Could not retrieve logs"
    else
      echo "No cloud-init logs found for $INSTANCE_ID"
    fi
  done
  
  echo ""
done

echo ""
echo "5. Auto Scaling Activities (last 10):"
aws autoscaling describe-scaling-activities \
  --region "$REGION" \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-items 10 \
  --query 'Activities[*].{Time:StartTime,Status:StatusCode,Description:Description,Cause:Cause}' \
  --output table

echo ""
echo "6. Health Check Configuration:"
aws autoscaling describe-auto-scaling-groups \
  --region "$REGION" \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].{HealthCheckType:HealthCheckType,HealthCheckGracePeriod:HealthCheckGracePeriod,DefaultCooldown:DefaultCooldown}' \
  --output table

echo ""
echo "7. Target Group Health (if ELB health checks):"
TARGET_GROUP_ARNS=$(aws autoscaling describe-auto-scaling-groups \
  --region "$REGION" \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].TargetGroupARNs[*]' \
  --output text)

if [ -n "$TARGET_GROUP_ARNS" ]; then
  for TG_ARN in $TARGET_GROUP_ARNS; do
    echo "Target Group: $TG_ARN"
    aws elbv2 describe-target-health \
      --region "$REGION" \
      --target-group-arn "$TG_ARN" \
      --query 'TargetHealthDescriptions[*].{Target:Target.Id,Health:TargetHealth.State,Description:TargetHealth.Description}' \
      --output table 2>/dev/null || echo "Could not get target health"
  done
else
  echo "No target groups attached"
fi

echo ""
echo "=== Recommendations ==="
echo ""

# Analyze the situation and provide recommendations
INSTANCE_COUNT=$(echo "$INSTANCE_IDS" | wc -w)
if [ "$INSTANCE_COUNT" -eq 0 ]; then
  echo "❌ No instances in ASG - Check launch template and capacity"
else
  echo "✅ Found $INSTANCE_COUNT instance(s) in ASG"
  
  # Check if any instances are in InService state
  INSERVICE_COUNT=$(aws autoscaling describe-auto-scaling-groups \
    --region "$REGION" \
    --auto-scaling-group-names "$ASG_NAME" \
    --query 'length(AutoScalingGroups[0].Instances[?LifecycleState==`InService`])' \
    --output text)
  
  if [ "$INSERVICE_COUNT" -eq 0 ]; then
    echo "❌ No instances are InService"
    echo ""
    echo "Common causes and solutions:"
    echo "1. User data script failing - Check cloud-init logs above"
    echo "2. Health check failing - Increase grace period or check target group health"
    echo "3. Still launching - Wait longer (user data can take 10-15 minutes)"
    echo ""
    echo "Quick fixes to try:"
    echo "1. Increase health check grace period:"
    echo "   aws autoscaling update-auto-scaling-group --auto-scaling-group-name $ASG_NAME --health-check-grace-period 1200"
    echo ""
    echo "2. Force instance refresh:"
    echo "   aws autoscaling start-instance-refresh --auto-scaling-group-name $ASG_NAME"
  else
    echo "✅ $INSERVICE_COUNT instance(s) are InService"
  fi
fi

echo ""
echo "Debug script completed!"