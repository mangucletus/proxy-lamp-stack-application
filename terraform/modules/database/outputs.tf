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

output "db_parameter_group_id" {
  description = "DB parameter group ID"
  value       = aws_db_parameter_group.proxy_lamp_mysql_params.id
}

output "db_option_group_id" {
  description = "DB option group ID"
  value       = aws_db_option_group.proxy_lamp_mysql_options.id
}

output "kms_key_id" {
  description = "KMS key ID for RDS encryption"
  value       = aws_kms_key.rds_encryption_key.key_id
}

output "kms_key_arn" {
  description = "KMS key ARN for RDS encryption"
  value       = aws_kms_key.rds_encryption_key.arn
}

output "kms_alias_name" {
  description = "KMS key alias name"
  value       = aws_kms_alias.rds_encryption_key_alias.name
}

output "secrets_manager_secret_arn" {
  description = "Secrets Manager secret ARN for database credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "secrets_manager_secret_name" {
  description = "Secrets Manager secret name for database credentials"
  value       = aws_secretsmanager_secret.db_credentials.name
}

output "read_replica_endpoint" {
  description = "Read replica endpoint"
  value       = var.create_read_replica ? aws_db_instance.proxy_lamp_mysql_replica[0].endpoint : ""
  sensitive   = true
}

output "read_replica_identifier" {
  description = "Read replica identifier"
  value       = var.create_read_replica ? aws_db_instance.proxy_lamp_mysql_replica[0].id : ""
}

output "cloudwatch_log_groups" {
  description = "CloudWatch log group names"
  value = {
    error   = aws_cloudwatch_log_group.mysql_error_log.name
    general = aws_cloudwatch_log_group.mysql_general_log.name
    slow    = aws_cloudwatch_log_group.mysql_slow_log.name
  }
}

output "sns_topic_arn" {
  description = "SNS topic ARN for RDS alerts"
  value       = aws_sns_topic.rds_alerts.arn
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarm ARNs"
  value = {
    cpu_utilization   = aws_cloudwatch_metric_alarm.database_cpu.arn
    database_connections = aws_cloudwatch_metric_alarm.database_connections.arn
    free_storage_space = aws_cloudwatch_metric_alarm.database_free_storage.arn
  }
}

output "enhanced_monitoring_role_arn" {
  description = "Enhanced monitoring IAM role ARN"
  value       = var.enable_enhanced_monitoring ? aws_iam_role.rds_enhanced_monitoring[0].arn : ""
}

output "database_summary" {
  description = "Summary of database configuration"
  value = {
    instance_identifier = aws_db_instance.proxy_lamp_mysql.id
    endpoint           = aws_db_instance.proxy_lamp_mysql.endpoint
    port               = aws_db_instance.proxy_lamp_mysql.port
    database_name      = aws_db_instance.proxy_lamp_mysql.db_name
    engine_version     = aws_db_instance.proxy_lamp_mysql.engine_version
    instance_class     = aws_db_instance.proxy_lamp_mysql.instance_class
    storage_type       = aws_db_instance.proxy_lamp_mysql.storage_type
    allocated_storage  = aws_db_instance.proxy_lamp_mysql.allocated_storage
    multi_az          = aws_db_instance.proxy_lamp_mysql.multi_az
    backup_retention  = aws_db_instance.proxy_lamp_mysql.backup_retention_period
    enhanced_monitoring = var.enable_enhanced_monitoring
    performance_insights = var.enable_performance_insights
    read_replica_created = var.create_read_replica
  }
  sensitive = true
}