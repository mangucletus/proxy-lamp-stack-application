#!/bin/bash

# Proxy LAMP Stack Deployment Helper Script
# This script helps with local development and testing

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
APP_DIR="$PROJECT_ROOT/app"

# Default values
AWS_REGION="eu-central-1"
KEY_NAME="proxy-lamp-keypair"

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi
    
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws")
    fi
    
    if ! command -v git &> /dev/null; then
        missing_tools+=("git")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing tools and try again."
        exit 1
    fi
    
    log_success "All prerequisites are installed"
}

# Check AWS credentials
check_aws_credentials() {
    log_info "Checking AWS credentials..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        echo "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
    
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    local user_arn
    user_arn=$(aws sts get-caller-identity --query Arn --output text)
    
    log_success "AWS credentials are valid"
    log_info "Account ID: $account_id"
    log_info "User/Role: $user_arn"
}

# Generate SSH key pair
generate_ssh_keys() {
    log_info "Generating SSH key pair..."
    
    if [ -f "$PROJECT_ROOT/$KEY_NAME" ]; then
        log_warning "SSH key pair already exists"
        read -p "Do you want to regenerate it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    
    ssh-keygen -t rsa -b 2048 -f "$PROJECT_ROOT/$KEY_NAME" -N "" -C "proxy-lamp-stack@$(date +%Y%m%d)"
    chmod 600 "$PROJECT_ROOT/$KEY_NAME"
    chmod 644 "$PROJECT_ROOT/$KEY_NAME.pub"
    
    log_success "SSH key pair generated: $KEY_NAME"
}

# Create S3 bucket for Terraform state
create_state_bucket() {
    log_info "Setting up Terraform state bucket..."
    
    local timestamp
    timestamp=$(date +%s)
    local bucket_name="proxy-lamp-stack-tfstate-$(whoami)-$timestamp"
    
    # Check if bucket already exists in main.tf
    if [ -f "$TERRAFORM_DIR/main.tf" ]; then
        local existing_bucket
        existing_bucket=$(grep -o 'bucket = "[^"]*"' "$TERRAFORM_DIR/main.tf" | cut -d'"' -f2 || echo "")
        
        if [ -n "$existing_bucket" ] && aws s3 ls "s3://$existing_bucket" &> /dev/null; then
            log_success "Terraform state bucket already exists: $existing_bucket"
            return 0
        fi
    fi
    
    # Create bucket
    if aws s3 mb "s3://$bucket_name" --region "$AWS_REGION"; then
        log_success "Created S3 bucket: $bucket_name"
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$bucket_name" \
            --versioning-configuration Status=Enabled
        
        # Enable encryption
        aws s3api put-bucket-encryption \
            --bucket "$bucket_name" \
            --server-side-encryption-configuration \
            '{
                "Rules": [
                    {
                        "ApplyServerSideEncryptionByDefault": {
                            "SSEAlgorithm": "AES256"
                        }
                    }
                ]
            }'
        
        log_info "Bucket versioning and encryption enabled"
        log_warning "Please update terraform/main.tf with the bucket name: $bucket_name"
    else
        log_error "Failed to create S3 bucket"
        exit 1
    fi
}

# Validate Terraform configuration
validate_terraform() {
    log_info "Validating Terraform configuration..."
    
    cd "$TERRAFORM_DIR"
    
    if ! terraform init -backend=false; then
        log_error "Terraform initialization failed"
        exit 1
    fi
    
    if ! terraform validate; then
        log_error "Terraform validation failed"
        exit 1
    fi
    
    log_success "Terraform configuration is valid"
}

# Plan Terraform deployment
plan_terraform() {
    log_info "Planning Terraform deployment..."
    
    cd "$TERRAFORM_DIR"
    
    if [ ! -f "$PROJECT_ROOT/$KEY_NAME.pub" ]; then
        log_error "Public key not found: $PROJECT_ROOT/$KEY_NAME.pub"
        log_info "Run: $0 generate-keys"
        exit 1
    fi
    
    local public_key
    public_key=$(cat "$PROJECT_ROOT/$KEY_NAME.pub")
    
    terraform init
    terraform plan \
        -var="public_key=$public_key" \
        -var="db_password=${DB_PASSWORD:-ProxySecurePass123!}" \
        -out=tfplan
    
    log_success "Terraform plan completed. Run 'terraform apply tfplan' to deploy."
}

# Apply Terraform deployment
apply_terraform() {
    log_info "Applying Terraform deployment..."
    
    cd "$TERRAFORM_DIR"
    
    if [ ! -f "tfplan" ]; then
        log_error "No Terraform plan found. Run: $0 plan"
        exit 1
    fi
    
    terraform apply tfplan
    
    if [ $? -eq 0 ]; then
        log_success "Terraform deployment completed successfully!"
        
        # Get outputs
        local load_balancer_dns
        load_balancer_dns=$(terraform output -raw load_balancer_dns 2>/dev/null || echo "Not available")
        
        if [ "$load_balancer_dns" != "Not available" ]; then
            log_success "Application URL: http://$load_balancer_dns"
            log_info "Health Check: http://$load_balancer_dns/health.php"
        fi
        
        log_info "It may take 10-15 minutes for the application to be fully available"
    else
        log_error "Terraform deployment failed"
        exit 1
    fi
}

# Destroy infrastructure
destroy_terraform() {
    log_warning "This will destroy ALL infrastructure!"
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    
    if [ "$REPLY" != "yes" ]; then
        log_info "Destruction cancelled"
        exit 0
    fi
    
    cd "$TERRAFORM_DIR"
    
    local public_key
    public_key=$(cat "$PROJECT_ROOT/$KEY_NAME.pub" 2>/dev/null || echo "dummy-key")
    
    terraform destroy \
        -var="public_key=$public_key" \
        -var="db_password=${DB_PASSWORD:-ProxySecurePass123!}" \
        -auto-approve
    
    log_success "Infrastructure destroyed"
}

# Check application health
check_health() {
    log_info "Checking application health..."
    
    cd "$TERRAFORM_DIR"
    
    local load_balancer_dns
    load_balancer_dns=$(terraform output -raw load_balancer_dns 2>/dev/null || echo "")
    
    if [ -z "$load_balancer_dns" ]; then
        log_error "Load balancer DNS not found. Is the infrastructure deployed?"
        exit 1
    fi
    
    log_info "Load Balancer DNS: $load_balancer_dns"
    
    # Check health endpoint
    local health_url="http://$load_balancer_dns/health.php"
    log_info "Checking health endpoint: $health_url"
    
    if command -v curl &> /dev/null; then
        local response
        response=$(curl -s -w "%{http_code}" "$health_url" -o /tmp/health_response.json 2>/dev/null || echo "000")
        
        if [ "$response" = "200" ]; then
            log_success "Application is healthy!"
            
            if [ -f "/tmp/health_response.json" ]; then
                local status
                status=$(jq -r '.status // "unknown"' /tmp/health_response.json 2>/dev/null || echo "unknown")
                local server
                server=$(jq -r '.server // "unknown"' /tmp/health_response.json 2>/dev/null || echo "unknown")
                
                log_info "Status: $status"
                log_info "Server: $server"
                
                # Show database status
                local db_status
                db_status=$(jq -r '.checks.database.status // "unknown"' /tmp/health_response.json 2>/dev/null || echo "unknown")
                log_info "Database: $db_status"
            fi
        else
            log_error "Application health check failed (HTTP $response)"
            exit 1
        fi
    else
        log_warning "curl not available, cannot check health endpoint"
    fi
    
    # Check main application
    log_info "Checking main application..."
    if curl -s -f "http://$load_balancer_dns/" > /dev/null; then
        log_success "Main application is accessible"
        log_info "Application URL: http://$load_balancer_dns/"
    else
        log_error "Main application is not accessible"
    fi
}

# Show help
show_help() {
    cat << EOF
Proxy LAMP Stack Deployment Helper

Usage: $0 <command>

Commands:
    check           Check prerequisites and AWS credentials
    generate-keys   Generate SSH key pair
    create-bucket   Create S3 bucket for Terraform state
    validate        Validate Terraform configuration
    plan           Plan Terraform deployment
    apply          Apply Terraform deployment
    destroy        Destroy all infrastructure
    health         Check application health
    full-deploy    Run complete deployment (check -> generate-keys -> validate -> plan -> apply)
    help           Show this help message

Environment Variables:
    AWS_REGION     AWS region (default: eu-central-1)
    DB_PASSWORD    Database password (default: ProxySecurePass123!)

Examples:
    $0 check                    # Check prerequisites
    $0 full-deploy             # Complete deployment
    $0 health                  # Check application health
    DB_PASSWORD=MyPass $0 plan # Plan with custom password

EOF
}

# Main script logic
main() {
    case "${1:-help}" in
        check)
            check_prerequisites
            check_aws_credentials
            ;;
        generate-keys)
            generate_ssh_keys
            ;;
        create-bucket)
            check_prerequisites
            check_aws_credentials
            create_state_bucket
            ;;
        validate)
            check_prerequisites
            validate_terraform
            ;;
        plan)
            check_prerequisites
            check_aws_credentials
            plan_terraform
            ;;
        apply)
            check_prerequisites
            check_aws_credentials
            apply_terraform
            ;;
        destroy)
            check_prerequisites
            check_aws_credentials
            destroy_terraform
            ;;
        health)
            check_health
            ;;
        full-deploy)
            check_prerequisites
            check_aws_credentials
            generate_ssh_keys
            validate_terraform
            plan_terraform
            read -p "Continue with deployment? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                apply_terraform
            else
                log_info "Deployment cancelled"
            fi
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: ${1:-}"
            show_help
            exit 1
            ;;
    esac
}

# Cleanup on exit
cleanup() {
    rm -f /tmp/health_response.json
}
trap cleanup EXIT

# Run main function
main "$@"