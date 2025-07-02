# Define the AWS region to deploy resources in
variable "aws_region" {
  description = "AWS region"   # A short description for documentation
  type        = string         # The type must be a string
  default     = "eu-central-1" # Updated region (Frankfurt)
}

# Define the EC2 instance type (hardware configuration)
variable "instance_type" {
  description = "EC2 instance type for web servers" # Explains the purpose of the variable
  type        = string                              # The type must be a string
  default     = "t3.micro"                          # Cost-effective instance type under free tier
}

# Name of the SSH key pair used to connect to the EC2 instances
variable "key_name" {
  description = "AWS key pair name for EC2 access" # Short description for the variable
  type        = string                             # Must be a string (e.g., "proxy-lamp-keypair")
  default     = "proxy-lamp-keypair"               # Updated default value with prefix
}

# The actual public key content to inject into instances for SSH access
variable "public_key" {
  description = "Public key for EC2 access" # What this key is for
  type        = string                      # Public key content as a string
  sensitive   = true                        # Hides value from CLI/UI output for security
}

# Root password for the RDS MySQL database (should be stored securely)
variable "db_password" {
  description = "MySQL database password for RDS instance" # Purpose of the password
  type        = string                                     # Must be a string
  sensitive   = true                                       # Hides from CLI/UI logs
  default     = "ProxySecurePass123!"                      # Updated default password with prefix
}

# Auto Scaling Group configuration variables
variable "min_size" {
  description = "Minimum number of instances in Auto Scaling Group"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of instances in Auto Scaling Group"
  type        = number
  default     = 6
}

variable "desired_capacity" {
  description = "Desired number of instances in Auto Scaling Group"
  type        = number
  default     = 2
}

# Database configuration variables
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS instance in GB"
  type        = number
  default     = 20
}

variable "db_backup_retention_period" {
  description = "Number of days to retain database backups"
  type        = number
  default     = 7
}

variable "db_multi_az" {
  description = "Enable Multi-AZ deployment for RDS"
  type        = bool
  default     = false # Set to true for production
}

# Load balancer configuration
variable "health_check_path" {
  description = "Health check path for load balancer target group"
  type        = string
  default     = "/health.php"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
}

variable "healthy_threshold" {
  description = "Number of consecutive successful health checks"
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Number of consecutive failed health checks"
  type        = number
  default     = 3
}

# Monitoring configuration
variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for EC2 instances"
  type        = bool
  default     = true
}

# Environment and naming variables
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "proxy-lamp-stack"
}