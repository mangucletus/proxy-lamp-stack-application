output "alb_sg_id" {
  description = "ID of the Application Load Balancer security group"
  value       = aws_security_group.proxy_lamp_alb_sg.id
}

output "web_sg_id" {
  description = "ID of the web tier security group"
  value       = aws_security_group.proxy_lamp_web_sg.id
}

output "database_sg_id" {
  description = "ID of the database security group"
  value       = aws_security_group.proxy_lamp_db_sg.id
}

output "endpoint_sg_id" {
  description = "ID of the VPC endpoints security group"
  value       = aws_security_group.proxy_lamp_endpoint_sg.id
}

output "monitoring_sg_id" {
  description = "ID of the monitoring security group"
  value       = aws_security_group.proxy_lamp_monitoring_sg.id
}

# Security Group ARNs
output "alb_sg_arn" {
  description = "ARN of the Application Load Balancer security group"
  value       = aws_security_group.proxy_lamp_alb_sg.arn
}

output "web_sg_arn" {
  description = "ARN of the web tier security group"
  value       = aws_security_group.proxy_lamp_web_sg.arn
}

output "database_sg_arn" {
  description = "ARN of the database security group"
  value       = aws_security_group.proxy_lamp_db_sg.arn
}

# Network ACL IDs
output "web_nacl_id" {
  description = "ID of the web tier Network ACL"
  value       = aws_network_acl.proxy_lamp_web_nacl.id
}

output "db_nacl_id" {
  description = "ID of the database tier Network ACL"
  value       = aws_network_acl.proxy_lamp_db_nacl.id
}

# Security groups list for reference
output "all_security_group_ids" {
  description = "List of all security group IDs"
  value = [
    aws_security_group.proxy_lamp_alb_sg.id,
    aws_security_group.proxy_lamp_web_sg.id,
    aws_security_group.proxy_lamp_db_sg.id,
    aws_security_group.proxy_lamp_endpoint_sg.id,
    aws_security_group.proxy_lamp_monitoring_sg.id
  ]
}

# Security configuration summary
output "security_summary" {
  description = "Summary of security configuration"
  value = {
    alb_security_group    = aws_security_group.proxy_lamp_alb_sg.name
    web_security_group    = aws_security_group.proxy_lamp_web_sg.name
    database_security_group = aws_security_group.proxy_lamp_db_sg.name
    monitoring_security_group = aws_security_group.proxy_lamp_monitoring_sg.name
    web_nacl             = aws_network_acl.proxy_lamp_web_nacl.id
    database_nacl        = aws_network_acl.proxy_lamp_db_nacl.id
  }
}