# terraform/modules/database/outputs.tf - FIXED VERSION

output "db_instance_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.proxy_lamp_mysql.id
}

output "db_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.proxy_lamp_mysql.endpoint
  sensitive   = true
}

output "db_port" {
  description = "RDS instance port"
  value       = aws_db_instance.proxy_lamp_mysql.port
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.proxy_lamp_mysql.db_name
}

output "db_username" {
  description = "Database username"
  value       = aws_db_instance.proxy_lamp_mysql.username
  sensitive   = true
}

output "db_password" {
  description = "Database password"
  value       = var.db_password != "" ? var.db_password : random_password.db_password[0].result
  sensitive   = true
}

output "db_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.proxy_lamp_mysql.arn
}

output "db_hosted_zone_id" {
  description = "RDS instance hosted zone ID"
  value       = aws_db_instance.proxy_lamp_mysql.hosted_zone_id
}

output "db_resource_id" {
  description = "RDS instance resource ID"
  value       = aws_db_instance.proxy_lamp_mysql.resource_id
}

output "db_subnet_group_id" {
  description = "DB subnet group ID"
  value       = aws_db_subnet_group.proxy_lamp_db_subnet_group.id
}

output "db_subnet_group_arn" {
  description = "DB subnet group ARN"
  value       = aws_db_subnet_group.proxy_lamp_db_subnet_group.arn
}

# REMOVED: Parameter group and option group outputs (using defaults now)
# REMOVED: KMS key outputs (using default encryption now)
# REMOVED: Enhanced monitoring outputs (not enabled)
# REMOVED: Read replica outputs (not created)

output "secrets_manager_secret_arn" {
  description = "Secrets Manager secret ARN for database credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "secrets_manager_secret_name" {
  description = "Secrets Manager secret name for database credentials"
  value       = aws_secretsmanager_secret.db_credentials.name
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarm ARNs"
  value = {
    cpu_utilization       = aws_cloudwatch_metric_alarm.database_cpu.arn
    database_connections  = aws_cloudwatch_metric_alarm.database_connections.arn
  }
}

output "database_summary" {
  description = "Summary of database configuration"
  value = {
    instance_identifier   = aws_db_instance.proxy_lamp_mysql.id
    endpoint             = aws_db_instance.proxy_lamp_mysql.endpoint
    port                 = aws_db_instance.proxy_lamp_mysql.port
    database_name        = aws_db_instance.proxy_lamp_mysql.db_name
    engine_version       = aws_db_instance.proxy_lamp_mysql.engine_version
    instance_class       = aws_db_instance.proxy_lamp_mysql.instance_class
    storage_type         = aws_db_instance.proxy_lamp_mysql.storage_type
    allocated_storage    = aws_db_instance.proxy_lamp_mysql.allocated_storage
    multi_az            = aws_db_instance.proxy_lamp_mysql.multi_az
    backup_retention    = aws_db_instance.proxy_lamp_mysql.backup_retention_period
    enhanced_monitoring = false
    performance_insights = false
  }
  sensitive = true
}