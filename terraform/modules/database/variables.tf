variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of private subnets for database"
  type        = list(string)
}

variable "database_sg_id" {
  description = "Security group ID for database"
  type        = string
}

variable "deployment_suffix" {
  description = "Unique suffix for resource naming to avoid conflicts"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Database engine configuration
variable "db_engine_version" {
  description = "MySQL engine version"
  type        = string
  default     = "8.0.35"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

# Database storage configuration
variable "db_allocated_storage" {
  description = "Allocated storage for RDS instance in GB"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Maximum allocated storage for RDS instance in GB"
  type        = number
  default     = 100
}

variable "db_storage_type" {
  description = "Storage type for RDS instance"
  type        = string
  default     = "gp3"
}

# Database configuration
variable "db_name" {
  description = "Name of the database"
  type        = string
  default     = "proxylamptodoapp"
}

variable "db_username" {
  description = "Username for database access"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Password for database access"
  type        = string
  sensitive   = true
  default     = ""
}

variable "db_port" {
  description = "Port for database access"
  type        = number
  default     = 3306
}

# Backup configuration
variable "db_backup_retention_period" {
  description = "Number of days to retain database backups"
  type        = number
  default     = 7
}

variable "db_backup_window" {
  description = "Backup window for RDS instance"
  type        = string
  default     = "03:00-04:00"
}

variable "db_maintenance_window" {
  description = "Maintenance window for RDS instance"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

# High availability configuration
variable "db_multi_az" {
  description = "Enable Multi-AZ deployment for RDS"
  type        = bool
  default     = false
}

# Monitoring configuration
variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for RDS"
  type        = bool
  default     = true
}

variable "enable_performance_insights" {
  description = "Enable Performance Insights for RDS"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Retention period for RDS logs in days"
  type        = number
  default     = 7
}

# Security configuration
variable "enable_deletion_protection" {
  description = "Enable deletion protection for RDS instance"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when deleting RDS instance"
  type        = bool
  default     = false
}

# Update configuration
variable "auto_minor_version_upgrade" {
  description = "Enable automatic minor version upgrades"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Apply changes immediately or during maintenance window"
  type        = bool
  default     = false
}

# Read replica configuration
variable "create_read_replica" {
  description = "Create a read replica for the database"
  type        = bool
  default     = false
}

variable "replica_instance_class" {
  description = "Instance class for read replica"
  type        = string
  default     = "db.t3.micro"
}

# Parameter group configuration
variable "enable_slow_query_log" {
  description = "Enable slow query log"
  type        = bool
  default     = true
}

variable "long_query_time" {
  description = "Threshold for slow query log in seconds"
  type        = number
  default     = 2
}

variable "enable_general_log" {
  description = "Enable general query log"
  type        = bool
  default     = true
}

# Connection configuration
variable "max_connections" {
  description = "Maximum number of database connections"
  type        = number
  default     = 1000
}

# Performance configuration
variable "innodb_buffer_pool_size_percent" {
  description = "Percentage of memory to allocate to InnoDB buffer pool"
  type        = number
  default     = 75
}