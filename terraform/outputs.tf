#-------------------------------
# Load Balancer Outputs
#-------------------------------
output "load_balancer_dns" {
  description = "DNS name of the Application Load Balancer"
  value       = module.load_balancer.load_balancer_dns
}

output "load_balancer_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = module.load_balancer.load_balancer_zone_id
}

output "load_balancer_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.load_balancer.load_balancer_arn
}

#-------------------------------
# Application URL Outputs
#-------------------------------
output "application_url" {
  description = "URL to access the load-balanced application"
  value       = "http://${module.load_balancer.load_balancer_dns}"
}

output "health_check_url" {
  description = "URL for application health checks"
  value       = "http://${module.load_balancer.load_balancer_dns}/health.php"
}

#-------------------------------
# Auto Scaling Group Outputs
#-------------------------------
output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = module.compute.autoscaling_group_arn
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = module.compute.autoscaling_group_name
}

output "instance_ips" {
  description = "Public IP addresses of EC2 instances (check AWS console for actual IPs)"
  value       = ["Check AWS EC2 console for instance IP addresses"]
}

#-------------------------------
# Database Outputs (Non-sensitive)
#-------------------------------
output "database_port" {
  description = "RDS MySQL database port"
  value       = module.database.db_port
}

output "database_name" {
  description = "RDS MySQL database name"
  value       = module.database.db_name
}

#-------------------------------
# Network Infrastructure Outputs
#-------------------------------
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

#-------------------------------
# Security Group Outputs
#-------------------------------
output "alb_security_group_id" {
  description = "ID of the Application Load Balancer security group"
  value       = module.security.alb_sg_id
}

output "web_security_group_id" {
  description = "ID of the web tier security group"
  value       = module.security.web_sg_id
}

output "database_security_group_id" {
  description = "ID of the database security group"
  value       = module.security.database_sg_id
}

#-------------------------------
# Monitoring Outputs
#-------------------------------
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = module.monitoring.dashboard_url
}

output "cloudwatch_log_group_names" {
  description = "Names of CloudWatch log groups"
  value       = module.monitoring.log_group_names
}

#-------------------------------
# SSH Connection Information
#-------------------------------
output "ssh_commands" {
  description = "SSH commands to connect to instances"
  value       = ["Use AWS EC2 console to get instance IP addresses, then: ssh -i your-private-key.pem ubuntu@INSTANCE_IP"]
}

#-------------------------------
# Deployment Information (Non-sensitive)
#-------------------------------
output "deployment_summary" {
  description = "Summary of deployed infrastructure"
  value = {
    region               = var.aws_region
    load_balancer_dns    = module.load_balancer.load_balancer_dns
    application_url      = "http://${module.load_balancer.load_balancer_dns}"
    health_check_url     = "http://${module.load_balancer.load_balancer_dns}/health.php"
    monitoring_dashboard = module.monitoring.dashboard_url
    deployment_timestamp = timestamp()
    note                 = "Check AWS EC2 console for instance details"
  }
  sensitive = true
}

#-------------------------------
# Sensitive Database Information
#-------------------------------
output "database_endpoint" {
  description = "RDS MySQL database endpoint"
  value       = module.database.db_endpoint
  sensitive   = true
}

#-------------------------------
# Terraform State Information
#-------------------------------
output "terraform_state_bucket" {
  description = "S3 bucket storing Terraform state"
  value       = "proxy-lamp-stack-tfstate-cletusmangu-1749764"
}

output "deployment_id" {
  description = "Unique deployment identifier"
  value       = random_id.deployment_id.hex
}