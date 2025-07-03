#!/bin/bash
# Proxy LAMP Stack Deployment Troubleshooting Script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
AWS_REGION="eu-central-1"

# Check if running from terraform directory
if [ ! -f "main.tf" ]; then
    if [ -f "terraform/main.tf" ]; then
        cd terraform
    else
        log_error "Please run this script from the project root or terraform directory"
        exit 1
    fi
fi

# Get deployment outputs
get_deployment_info() {
    log_info "Getting deployment information..."
    
    if ! terraform output > /dev/null 2>&1; then
        log_error "No terraform outputs found. Is the infrastructure deployed?"
        exit 1
    fi
    
    LOAD_BALANCER_DNS=$(terraform output -raw load_balancer_dns 2>/dev/null || echo "")
    ASG_NAME=$(terraform output -raw autoscaling_group_name 2>/dev/null || echo "")
    
    if [ -z "$LOAD_BALANCER_DNS" ] || [ -z "$ASG_NAME" ]; then
        log_error "Could not get required deployment information"
        exit 1
    fi
    
    log_success "Found deployment:"
    echo "  Load Balancer: $LOAD_BALANCER_DNS"
    echo "  Auto Scaling Group: $ASG_NAME"
}

# Check Auto Scaling Group status
check_asg_status() {
    log_info "Checking Auto Scaling Group status..."
    
    # Get ASG information
    ASG_INFO=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$ASG_NAME" \
        --region "$AWS_REGION" \
        --output json)
    
    DESIRED_CAPACITY=$(echo "$ASG_INFO" | jq -r '.AutoScalingGroups[0].DesiredCapacity')
    MIN_SIZE=$(echo "$ASG_INFO" | jq -r '.AutoScalingGroups[0].MinSize')
    MAX_SIZE=$(echo "$ASG_INFO" | jq -r '.AutoScalingGroups[0].MaxSize')
    
    echo "  Desired Capacity: $DESIRED_CAPACITY"
    echo "  Min Size: $MIN_SIZE"
    echo "  Max Size: $MAX_SIZE"
    
    # Get instance information
    INSTANCES=$(echo "$ASG_INFO" | jq -r '.AutoScalingGroups[0].Instances[]')
    INSTANCE_COUNT=$(echo "$ASG_INFO" | jq -r '.AutoScalingGroups[0].Instances | length')
    
    echo "  Current Instance Count: $INSTANCE_COUNT"
    
    if [ "$INSTANCE_COUNT" -eq 0 ]; then
        log_error "No instances found in Auto Scaling Group!"
        return 1
    fi
    
    # Check instance states
    echo "  Instance Status:"
    echo "$ASG_INFO" | jq -r '.AutoScalingGroups[0].Instances[] | "    \(.InstanceId): \(.LifecycleState) (\(.HealthStatus))"'
    
    # Get running instances
    RUNNING_INSTANCES=$(aws ec2 describe-instances \
        --instance-ids $(echo "$ASG_INFO" | jq -r '.AutoScalingGroups[0].Instances[].InstanceId' | tr '\n' ' ') \
        --region "$AWS_REGION" \
        --query 'Reservations[].Instances[?State.Name==`running`].[InstanceId,PublicIpAddress,PrivateIpAddress]' \
        --output table)
    
    echo "  Running Instances:"
    echo "$RUNNING_INSTANCES"
}

# Check Load Balancer status
check_load_balancer_status() {
    log_info "Checking Load Balancer status..."
    
    # Get load balancer information
    LB_ARN=$(aws elbv2 describe-load-balancers \
        --region "$AWS_REGION" \
        --query "LoadBalancers[?DNSName=='$LOAD_BALANCER_DNS'].LoadBalancerArn" \
        --output text)
    
    if [ -z "$LB_ARN" ] || [ "$LB_ARN" = "None" ]; then
        log_error "Could not find load balancer with DNS: $LOAD_BALANCER_DNS"
        return 1
    fi
    
    # Get target group information
    TARGET_GROUPS=$(aws elbv2 describe-target-groups \
        --load-balancer-arn "$LB_ARN" \
        --region "$AWS_REGION" \
        --output json)
    
    TG_ARN=$(echo "$TARGET_GROUPS" | jq -r '.TargetGroups[0].TargetGroupArn')
    TG_NAME=$(echo "$TARGET_GROUPS" | jq -r '.TargetGroups[0].TargetGroupName')
    
    echo "  Target Group: $TG_NAME"
    
    # Check target health
    TARGET_HEALTH=$(aws elbv2 describe-target-health \
        --target-group-arn "$TG_ARN" \
        --region "$AWS_REGION" \
        --output table)
    
    echo "  Target Health:"
    echo "$TARGET_HEALTH"
}

# Test application connectivity
test_application() {
    log_info "Testing application connectivity..."
    
    # Test DNS resolution
    if nslookup "$LOAD_BALANCER_DNS" > /dev/null 2>&1; then
        log_success "DNS resolution works"
    else
        log_error "DNS resolution failed"
        return 1
    fi
    
    # Test main application
    echo "Testing main application..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$LOAD_BALANCER_DNS/" --max-time 10 || echo "000")
    
    if [ "$HTTP_CODE" = "200" ]; then
        log_success "Main application responding (HTTP $HTTP_CODE)"
    else
        log_warning "Main application not responding (HTTP $HTTP_CODE)"
    fi
    
    # Test health endpoint
    echo "Testing health endpoint..."
    HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$LOAD_BALANCER_DNS/health.php" --max-time 10 || echo "000")
    
    if [ "$HEALTH_CODE" = "200" ]; then
        log_success "Health endpoint responding (HTTP $HEALTH_CODE)"
        
        # Get health details
        HEALTH_RESPONSE=$(curl -s "http://$LOAD_BALANCER_DNS/health.php" --max-time 10 || echo "{}")
        if command -v jq >/dev/null 2>&1; then
            echo "Health Status:"
            echo "$HEALTH_RESPONSE" | jq . 2>/dev/null || echo "$HEALTH_RESPONSE"
        fi
    else
        log_warning "Health endpoint not responding (HTTP $HEALTH_CODE)"
    fi
    
    # Overall status
    if [ "$HTTP_CODE" = "200" ] || [ "$HEALTH_CODE" = "200" ]; then
        log_success "Application is accessible!"
        echo "  Application URL: http://$LOAD_BALANCER_DNS"
        echo "  Health Check URL: http://$LOAD_BALANCER_DNS/health.php"
    else
        log_error "Application is not accessible"
        return 1
    fi
}

# Check instance logs
check_instance_logs() {
    local instance_ip=$1
    local private_key_path=$2
    
    log_info "Checking logs on instance $instance_ip..."
    
    if [ ! -f "$private_key_path" ]; then
        log_error "Private key not found: $private_key_path"
        return 1
    fi
    
    chmod 600 "$private_key_path"
    
    # Test SSH connection
    if ! timeout 10 ssh -i "$private_key_path" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@"$instance_ip" "echo 'SSH OK'" 2>/dev/null; then
        log_error "Cannot SSH to instance $instance_ip"
        return 1
    fi
    
    echo "Getting instance logs..."
    ssh -i "$private_key_path" -o StrictHostKeyChecking=no ubuntu@"$instance_ip" "
        echo '=== System Status ==='
        uptime
        echo
        echo '=== Apache Status ==='
        systemctl status apache2 --no-pager || echo 'Apache not running'
        echo
        echo '=== User Data Log (last 30 lines) ==='
        tail -30 /var/log/user-data.log 2>/dev/null || echo 'No user data log'
        echo
        echo '=== Apache Error Log (last 10 lines) ==='
        sudo tail -10 /var/log/apache2/error.log 2>/dev/null || echo 'No Apache error log'
        echo
        echo '=== Application Files ==='
        ls -la /var/www/html/ 2>/dev/null || echo 'No web files'
        echo
        echo '=== Disk Usage ==='
        df -h
        echo
        echo '=== Memory Usage ==='
        free -h
    " 2>/dev/null || log_error "Could not retrieve logs from $instance_ip"
}

# Main troubleshooting function
main() {
    local command=${1:-"all"}
    
    case "$command" in
        "deployment")
            get_deployment_info
            ;;
        "asg")
            get_deployment_info
            check_asg_status
            ;;
        "lb")
            get_deployment_info
            check_load_balancer_status
            ;;
        "app")
            get_deployment_info
            test_application
            ;;
        "logs")
            if [ $# -lt 3 ]; then
                echo "Usage: $0 logs <instance_ip> <private_key_path>"
                exit 1
            fi
            check_instance_logs "$2" "$3"
            ;;
        "all")
            get_deployment_info
            echo
            check_asg_status
            echo
            check_load_balancer_status
            echo
            test_application
            ;;
        *)
            echo "Usage: $0 [deployment|asg|lb|app|logs|all]"
            echo
            echo "Commands:"
            echo "  deployment  - Show deployment information"
            echo "  asg         - Check Auto Scaling Group status"
            echo "  lb          - Check Load Balancer status"
            echo "  app         - Test application connectivity"
            echo "  logs        - Check instance logs (requires IP and key path)"
            echo "  all         - Run all checks (default)"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"