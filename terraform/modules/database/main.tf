# DB Subnet Group for RDS
resource "aws_db_subnet_group" "proxy_lamp_db_subnet_group" {
  name       = "proxy-lamp-db-subnet-group-${var.deployment_suffix}"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "proxy-lamp-db-subnet-group-${var.deployment_suffix}"
  })
}

# Random password for database (if not provided)
resource "random_password" "db_password" {
  count   = var.db_password == "" ? 1 : 0
  length  = 16
  special = true
}

# RDS MySQL Instance
resource "aws_db_instance" "proxy_lamp_mysql" {
  identifier = "proxy-lamp-mysql-${var.deployment_suffix}"

  # Engine configuration
  engine         = "mysql"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  # Storage configuration
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = var.db_storage_type
  storage_encrypted     = true
  kms_key_id           = aws_kms_key.rds_encryption_key.arn

  # Database configuration
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password != "" ? var.db_password : random_password.db_password[0].result

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.proxy_lamp_db_subnet_group.name
  vpc_security_group_ids = [var.database_sg_id]
  port                   = var.db_port

  # Backup configuration
  backup_retention_period = var.db_backup_retention_period
  backup_window          = var.db_backup_window
  maintenance_window     = var.db_maintenance_window
  copy_tags_to_snapshot  = true

  # High Availability
  multi_az = var.db_multi_az

  # Monitoring
  monitoring_interval = var.enable_enhanced_monitoring ? 60 : 0
  monitoring_role_arn = var.enable_enhanced_monitoring ? aws_iam_role.rds_enhanced_monitoring[0].arn : null

  # Performance Insights
  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_retention_period = var.enable_performance_insights ? 7 : null
  performance_insights_kms_key_id      = var.enable_performance_insights ? aws_kms_key.rds_encryption_key.arn : null

  # Security
  publicly_accessible = false
  deletion_protection = var.enable_deletion_protection

  # Final snapshot
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "proxy-lamp-mysql-final-snapshot-${var.deployment_suffix}-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # Parameter group
  parameter_group_name = aws_db_parameter_group.proxy_lamp_mysql_params.name

  # Option group
  option_group_name = aws_db_option_group.proxy_lamp_mysql_options.name

  # Auto minor version upgrade
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  # Apply changes immediately or during maintenance window
  apply_immediately = var.apply_immediately

  tags = merge(var.tags, {
    Name = "proxy-lamp-mysql-${var.deployment_suffix}"
    Type = "RDS MySQL Database"
  })

  depends_on = [
    aws_db_subnet_group.proxy_lamp_db_subnet_group,
    aws_kms_key.rds_encryption_key
  ]
}

# KMS key for RDS encryption
resource "aws_kms_key" "rds_encryption_key" {
  description             = "KMS key for RDS encryption - ${var.deployment_suffix}"
  deletion_window_in_days = 7

  tags = merge(var.tags, {
    Name = "proxy-lamp-rds-encryption-key-${var.deployment_suffix}"
  })
}

resource "aws_kms_alias" "rds_encryption_key_alias" {
  name          = "alias/proxy-lamp-rds-${var.deployment_suffix}"
  target_key_id = aws_kms_key.rds_encryption_key.key_id
}

# DB Parameter Group for MySQL optimization
resource "aws_db_parameter_group" "proxy_lamp_mysql_params" {
  family = "mysql8.0"
  name   = "proxy-lamp-mysql-params-${var.deployment_suffix}"

  parameter {
    name  = "innodb_buffer_pool_size"
    value = "{DBInstanceClassMemory*3/4}"
  }

  parameter {
    name  = "max_connections"
    value = "1000"
  }

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"
  }

  parameter {
    name  = "general_log"
    value = "1"
  }

  parameter {
    name  = "log_queries_not_using_indexes"
    value = "1"
  }

  tags = merge(var.tags, {
    Name = "proxy-lamp-mysql-params-${var.deployment_suffix}"
  })
}

# DB Option Group
resource "aws_db_option_group" "proxy_lamp_mysql_options" {
  name                     = "proxy-lamp-mysql-options-${var.deployment_suffix}"
  option_group_description = "Option group for Proxy LAMP MySQL"
  engine_name              = "mysql"
  major_engine_version     = "8.0"

  tags = merge(var.tags, {
    Name = "proxy-lamp-mysql-options-${var.deployment_suffix}"
  })
}

# Enhanced Monitoring IAM Role
resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.enable_enhanced_monitoring ? 1 : 0
  name  = "proxy-lamp-rds-enhanced-monitoring-${var.deployment_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count      = var.enable_enhanced_monitoring ? 1 : 0
  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Read Replica (optional for production)
resource "aws_db_instance" "proxy_lamp_mysql_replica" {
  count = var.create_read_replica ? 1 : 0

  identifier              = "proxy-lamp-mysql-replica-${var.deployment_suffix}"
  replicate_source_db     = aws_db_instance.proxy_lamp_mysql.identifier
  instance_class          = var.replica_instance_class
  publicly_accessible     = false
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  # Monitoring
  monitoring_interval = var.enable_enhanced_monitoring ? 60 : 0
  monitoring_role_arn = var.enable_enhanced_monitoring ? aws_iam_role.rds_enhanced_monitoring[0].arn : null

  # Performance Insights
  performance_insights_enabled = var.enable_performance_insights

  tags = merge(var.tags, {
    Name = "proxy-lamp-mysql-replica-${var.deployment_suffix}"
    Type = "RDS MySQL Read Replica"
  })
}

# CloudWatch Log Groups for RDS logs
resource "aws_cloudwatch_log_group" "mysql_error_log" {
  name              = "/aws/rds/instance/proxy-lamp-mysql-${var.deployment_suffix}/error"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "proxy-lamp-mysql-error-log-${var.deployment_suffix}"
  })
}

resource "aws_cloudwatch_log_group" "mysql_general_log" {
  name              = "/aws/rds/instance/proxy-lamp-mysql-${var.deployment_suffix}/general"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "proxy-lamp-mysql-general-log-${var.deployment_suffix}"
  })
}

resource "aws_cloudwatch_log_group" "mysql_slow_log" {
  name              = "/aws/rds/instance/proxy-lamp-mysql-${var.deployment_suffix}/slowquery"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "proxy-lamp-mysql-slow-log-${var.deployment_suffix}"
  })
}

# CloudWatch Alarms for RDS monitoring
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "proxy-lamp-db-cpu-${var.deployment_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = [aws_sns_topic.rds_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.proxy_lamp_mysql.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  alarm_name          = "proxy-lamp-db-connections-${var.deployment_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "120"
  statistic           = "Average"
  threshold           = "800"
  alarm_description   = "This metric monitors RDS connection count"
  alarm_actions       = [aws_sns_topic.rds_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.proxy_lamp_mysql.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_free_storage" {
  alarm_name          = "proxy-lamp-db-free-storage-${var.deployment_suffix}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "120"
  statistic           = "Average"
  threshold           = "2000000000"  # 2GB in bytes
  alarm_description   = "This metric monitors RDS free storage space"
  alarm_actions       = [aws_sns_topic.rds_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.proxy_lamp_mysql.id
  }

  tags = var.tags
}

# SNS topic for RDS alerts
resource "aws_sns_topic" "rds_alerts" {
  name = "proxy-lamp-rds-alerts-${var.deployment_suffix}"

  tags = merge(var.tags, {
    Name = "proxy-lamp-rds-alerts-${var.deployment_suffix}"
  })
}

# Secrets Manager for database credentials
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "proxy-lamp-db-credentials-${var.deployment_suffix}"
  description = "Database credentials for Proxy LAMP stack"

  tags = merge(var.tags, {
    Name = "proxy-lamp-db-credentials-${var.deployment_suffix}"
  })
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password != "" ? var.db_password : random_password.db_password[0].result
    endpoint = aws_db_instance.proxy_lamp_mysql.endpoint
    port     = aws_db_instance.proxy_lamp_mysql.port
    dbname   = var.db_name
  })
}