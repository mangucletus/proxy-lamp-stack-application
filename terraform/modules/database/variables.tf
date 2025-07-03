# terraform/modules/database/variables.tf - FIXED VERSION

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
  default     = "db.t3.small"
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
  default     = "gp2"  # Changed from gp3 for compatibility
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

# High availability configuration - REMOVED multi_az (not supported by t3.micro)

# Monitoring configuration - REMOVED enhanced monitoring and performance insights

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