#!/bin/bash
# ASG Debug Script - Run this to check what's happening with your deployment

set -e

echo "🔍 Debugging Auto Scaling Group Issues..."

cd terraform

# Get ASG name
ASG_NAME=$(terraform output -raw autoscaling_group_name 2>/dev/null || echo "")
if [ -z "$ASG_NAME" ]; then
    echo "❌ Could not get ASG name from Terraform. Make sure terraform apply completed for basic resources."
    exit 1
fi

echo "✅ Auto Scaling Group: $ASG_NAME"

# Check ASG status
echo ""
echo "📊 ASG Status:"
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" \
    --query 'AutoScalingGroups[0].{MinSize:MinSize,MaxSize:MaxSize,DesiredCapacity:DesiredCapacity,HealthCheckType:HealthCheckType,HealthCheckGracePeriod:HealthCheckGracePeriod}' \
    --output table

# Check instances in ASG
echo ""
echo "🖥️  Instances in ASG:"
INSTANCES=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" \
    --query 'AutoScalingGroups[0].Instances[*].{InstanceId:InstanceId,State:LifecycleState,Health:HealthStatus,AZ:AvailabilityZone}' \
    --output table)

echo "$INSTANCES"

# Get instance IDs
INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" \
    --query 'AutoScalingGroups[0].Instances[*].InstanceId' --output text)

if [ -n "$INSTANCE_IDS" ]; then
    echo ""
    echo "🔍 Instance Details:"
    for INSTANCE_ID in $INSTANCE_IDS; do
        echo ""
        echo "--- Instance: $INSTANCE_ID ---"
        
        # Get instance status
        INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "unknown")
        echo "EC2 State: $INSTANCE_STATE"
        
        # Get instance checks
        STATUS_CHECKS=$(aws ec2 describe-instance-status --instance-ids "$INSTANCE_ID" \
            --query 'InstanceStatuses[0].{SystemStatus:SystemStatus.Status,InstanceStatus:InstanceStatus.Status}' \
            --output table 2>/dev/null || echo "No status checks available")
        echo "Status Checks:"
        echo "$STATUS_CHECKS"
        
        # Get user data logs if possible (via Systems Manager)
        echo "Checking user data execution..."
        aws ssm send-command --instance-ids "$INSTANCE_ID" \
            --document-name "AWS-RunShellScript" \
            --parameters 'commands=["tail -20 /var/log/cloud-init-output.log"]' \
            --query 'Command.CommandId' --output text >/dev/null 2>&1 && \
            echo "✅ SSM available - check AWS Console for user data logs" || \
            echo "❌ SSM not available - check EC2 Console for logs"
        
        # Try to get public IP for SSH
        PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null || echo "None")
        if [ "$PUBLIC_IP" != "None" ] && [ "$PUBLIC_IP" != "null" ]; then
            echo "Public IP: $PUBLIC_IP"
            echo "SSH Command: ssh -i your-private-key.pem ubuntu@$PUBLIC_IP"
            echo "Health Check: curl http://$PUBLIC_IP/health.php"
        fi
    done
else
    echo "❌ No instances found in ASG!"
fi

# Check Load Balancer Target Health
echo ""
echo "🎯 Load Balancer Target Health:"
TG_ARN=$(terraform output -raw load_balancer_arn 2>/dev/null | sed 's/.*loadbalancer/targetgroup/' | sed 's/loadbalancer.*//')
if [ -n "$TG_ARN" ]; then
    # This might fail, but let's try
    LB_DNS=$(terraform output -raw load_balancer_dns 2>/dev/null || echo "")
    echo "Load Balancer DNS: $LB_DNS"
    
    # Get target group from ALB
    ALB_ARN=$(terraform output -raw load_balancer_arn 2>/dev/null || echo "")
    if [ -n "$ALB_ARN" ]; then
        TARGET_GROUPS=$(aws elbv2 describe-target-groups --load-balancer-arn "$ALB_ARN" \
            --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")
        
        if [ -n "$TARGET_GROUPS" ] && [ "$TARGET_GROUPS" != "None" ]; then
            echo "Target Group Health:"
            aws elbv2 describe-target-health --target-group-arn "$TARGET_GROUPS" \
                --query 'TargetHealthDescriptions[*].{Target:Target.Id,Port:Target.Port,Health:TargetHealth.State,Reason:TargetHealth.Reason}' \
                --output table 2>/dev/null || echo "Could not get target health"
        fi
    fi
else
    echo "Could not determine target group ARN"
fi

echo ""
echo "🔧 Troubleshooting Tips:"
echo "1. Check instance user data logs in EC2 Console"
echo "2. SSH to instances and check Apache status: systemctl status apache2"
echo "3. Test health endpoint manually: curl http://localhost/health.php"
echo "4. Check security groups allow port 80 from load balancer"
echo "5. Verify database connectivity if app requires it"
echo ""
echo "📝 Common Issues:"
echo "- User data script failing (check /var/log/cloud-init-output.log)"
echo "- Health check path not responding (check Apache/PHP setup)"
echo "- Security group blocking health checks"
echo "- Database connection issues"
echo "- AMI compatibility problems"