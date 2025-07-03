# Define the AWS region to deploy resources in
variable "aws_region" {
  description = "AWS region"   
  type        = string         
  default     = "eu-central-1" 
}

# FIXED: Define the EC2 instance type (upgraded for better performance)
variable "instance_type" {
  description = "EC2 instance type for web servers" 
  type        = string                              
  default     = "t3.small"                          # FIXED: Changed from t3.micro to t3.small
}

# Name of the SSH key pair used to connect to the EC2 instances
variable "key_name" {
  description = "AWS key pair name for EC2 access" 
  type        = string                             
  default     = "proxy-lamp-keypair"               
}

# The actual public key content to inject into instances for SSH access
variable "public_key" {
  description = "Public key for EC2 access" 
  type        = string                      
  sensitive   = true                        
}

# Root password for the RDS MySQL database (should be stored securely)
variable "db_password" {
  description = "MySQL database password for RDS instance" 
  type        = string                                     
  sensitive   = true                                       
  default     = "ProxySecurePass123!"                      
}

# FIXED: Auto Scaling Group configuration with more stable defaults
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

# FIXED: Database configuration with better defaults
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.small"  # FIXED: Changed from db.t3.micro to db.t3.small
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

# FIXED: Load balancer configuration with better health check settings
variable "health_check_path" {
  description = "Health check path for load balancer target group"
  type        = string
  default     = "/"  # FIXED: Changed from "/health.php" to "/" for initial setup
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30  # FIXED: Reduced from 60 to 30
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 10  # FIXED: Reduced from 15 to 10
}

variable "healthy_threshold" {
  description = "Number of consecutive successful health checks"
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Number of consecutive failed health checks"
  type        = number
  default     = 3  # FIXED: Reduced from 5 to 3
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