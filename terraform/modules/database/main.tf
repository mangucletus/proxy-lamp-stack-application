# terraform/modules/database/main.tf - FIXED VERSION

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

# FIXED: Simplified RDS MySQL Instance Configuration
resource "aws_db_instance" "proxy_lamp_mysql" {
  identifier = "proxy-lamp-mysql-${var.deployment_suffix}"

  # Engine configuration
  engine         = "mysql"
  engine_version = "8.0.35"  # Stable version
  instance_class = var.db_instance_class

  # Storage configuration - FIXED: Simplified for compatibility
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp2"  # Changed from gp3 to gp2 for compatibility
  storage_encrypted     = true

  # Database configuration
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password != "" ? var.db_password : random_password.db_password[0].result

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.proxy_lamp_db_subnet_group.name
  vpc_security_group_ids = [var.database_sg_id]
  port                   = var.db_port
  publicly_accessible    = false

  # Backup configuration
  backup_retention_period = var.db_backup_retention_period
  backup_window          = var.db_backup_window
  maintenance_window     = var.db_maintenance_window
  copy_tags_to_snapshot  = true

  # High Availability - FIXED: Disabled for t3.micro
  multi_az = false  # t3.micro doesn't support Multi-AZ

  # Monitoring - FIXED: Disabled features not supported by t3.micro
  monitoring_interval = 0  # Disabled enhanced monitoring
  monitoring_role_arn = null

  # Performance Insights - FIXED: Disabled for t3.micro compatibility
  performance_insights_enabled = false

  # Security
  deletion_protection = var.enable_deletion_protection

  # Final snapshot
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "proxy-lamp-mysql-final-snapshot-${var.deployment_suffix}-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # FIXED: Use default parameter group to avoid compatibility issues
  parameter_group_name = "default.mysql8.0"

  # FIXED: Use default option group
  option_group_name = "default:mysql-8-0"

  # Auto minor version upgrade
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  # Apply changes immediately or during maintenance window
  apply_immediately = var.apply_immediately

  # FIXED: Remove depends_on to avoid circular dependencies
  depends_on = [aws_db_subnet_group.proxy_lamp_db_subnet_group]

  tags = merge(var.tags, {
    Name = "proxy-lamp-mysql-${var.deployment_suffix}"
    Type = "RDS MySQL Database"
  })
}

# REMOVED: KMS key, custom parameter group, option group to avoid compatibility issues
# REMOVED: Enhanced monitoring IAM role since we're not using enhanced monitoring
# REMOVED: Read replica since it's not needed for this setup

# CloudWatch Alarms for RDS monitoring - SIMPLIFIED
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
  threshold           = "80"  # Reduced threshold for t3.micro
  alarm_description   = "This metric monitors RDS connection count"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.proxy_lamp_mysql.id
  }

  tags = var.tags
}

# Secrets Manager for database credentials - SIMPLIFIED
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