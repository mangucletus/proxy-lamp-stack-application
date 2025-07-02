#-------------------------------
# Load Balancer Outputs
#-------------------------------
output "load_balancer_dns" {
  description = "DNS name of the Application Load Balancer"
  value       = module.load_balancer.load_balancer_dns
  # Primary endpoint for accessing the application through the load balancer
}

output "load_balancer_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = module.load_balancer.load_balancer_zone_id
  # Used for Route53 alias records if needed
}

output "load_balancer_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.load_balancer.load_balancer_arn
  # Used for monitoring and CloudWatch configuration
}

#-------------------------------
# Application URL Outputs
#-------------------------------
output "application_url" {
  description = "URL to access the load-balanced application"
  value       = "http://${module.load_balancer.load_balancer_dns}"
  # Constructs the HTTP URL using the load balancer DNS
}

output "health_check_url" {
  description = "URL for application health checks"
  value       = "http://${module.load_balancer.load_balancer_dns}/health.php"
  # Health check endpoint for monitoring
}

#-------------------------------
# Auto Scaling Group Outputs
#-------------------------------
output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = module.compute.autoscaling_group_arn
  # Used for monitoring and scaling policies
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = module.compute.autoscaling_group_name
  # Used for CloudWatch monitoring and scaling policies
}

output "instance_ips" {
  description = "Public IP addresses of EC2 instances"
  value       = module.compute.instance_ips
  # Used by deployment scripts to SSH into instances
}

#-------------------------------
# Database Outputs
#-------------------------------
output "database_endpoint" {
  description = "RDS MySQL database endpoint"
  value       = module.database.db_endpoint
  sensitive   = true
  # Database connection endpoint (marked sensitive)
}

output "database_port" {
  description = "RDS MySQL database port"
  value       = module.database.db_port
  # Database connection port
}

output "database_name" {
  description = "RDS MySQL database name"
  value       = module.database.db_name
  # Database name for application configuration
}

#-------------------------------
# Network Infrastructure Outputs
#-------------------------------
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
  # VPC identifier for reference
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
  # Public subnet identifiers
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
  # Private subnet identifiers for database
}

#-------------------------------
# Security Group Outputs
#-------------------------------
output "alb_security_group_id" {
  description = "ID of the Application Load Balancer security group"
  value       = module.security.alb_sg_id
  # ALB security group identifier
}

output "web_security_group_id" {
  description = "ID of the web tier security group"
  value       = module.security.web_sg_id
  # Web tier security group identifier
}

output "database_security_group_id" {
  description = "ID of the database security group"
  value       = module.security.database_sg_id
  # Database security group identifier
}

#-------------------------------
# Monitoring Outputs
#-------------------------------
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = module.monitoring.dashboard_url
  # Direct link to monitoring dashboard
}

output "cloudwatch_log_group_names" {
  description = "Names of CloudWatch log groups"
  value       = module.monitoring.log_group_names
  # Log group names for troubleshooting
}

#-------------------------------
# SSH Connection Information
#-------------------------------
output "ssh_commands" {
  description = "SSH commands to connect to instances"
  value = [
    for ip in module.compute.instance_ips :
    "ssh -i your-private-key.pem ubuntu@${ip}"
  ]
  # Ready-to-use SSH commands for each instance
}

#-------------------------------
# Deployment Information
#-------------------------------
output "deployment_summary" {
  description = "Summary of deployed infrastructure"
  value = {
    region               = var.aws_region
    load_balancer_dns    = module.load_balancer.load_balancer_dns
    application_url      = "http://${module.load_balancer.load_balancer_dns}"
    health_check_url     = "http://${module.load_balancer.load_balancer_dns}/health.php"
    instance_count       = length(module.compute.instance_ips)
    database_endpoint    = module.database.db_endpoint
    monitoring_dashboard = module.monitoring.dashboard_url
    deployment_timestamp = timestamp()
  }
  # Comprehensive deployment summary
}

#-------------------------------
# Terraform State Information
#-------------------------------
output "terraform_state_bucket" {
  description = "S3 bucket storing Terraform state"
  value       = "proxy-lamp-stack-tfstate-cletusmangu-1749764"
  # State bucket reference
}

output "deployment_id" {
  description = "Unique deployment identifier"
  value       = random_id.deployment_id.hex
  # Unique identifier for this deployment
}