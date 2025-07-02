# Define the AWS region to deploy resources in
variable "aws_region" {
  description = "AWS region"      # A short description for documentation
  type        = string            # The type must be a string
  default     = "eu-central-1"    # Updated region (Frankfurt)
}

# Define the EC2 instance type (hardware configuration)
variable "instance_type" {
  description = "EC2 instance type"   # Explains the purpose of the variable
  type        = string                # The type must be a string
  default     = "t3.micro"            # Cost-effective instance type under free tier
}

# Name of the SSH key pair used to connect to the EC2 instance
variable "key_name" {
  description = "AWS key pair name"   # Short description for the variable
  type        = string                # Must be a string (e.g., "proxy-lamp-keypair")
  default     = "proxy-lamp-keypair"  # Updated default value with prefix
}

# The actual public key content to inject into the instance for SSH access
variable "public_key" {
  description = "Public key for EC2 access"  # What this key is for
  type        = string                       # Public key content as a string
  sensitive   = true                         # Hides value from CLI/UI output for security
}

variable "public_subnet_ids" {
  description = "IDs of the public subnets where EC2 instances will be launched"
  type        = list(string)
}

variable "web_sg_id" {
  description = "ID of the web security group to attach to EC2 instances"
  type        = string
}

variable "target_group_arn" {
  description = "ARN of the load balancer target group"
  type        = string
}

variable "db_endpoint" {
  description = "RDS database endpoint"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "RDS database password"
  type        = string
  sensitive   = true
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

# Auto Scaling Group configuration
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

# Instance configuration
variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 20
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for EC2 instances"
  type        = bool
  default     = true
}

# Auto Scaling configuration
variable "cpu_scale_up_threshold" {
  description = "CPU utilization threshold to trigger scale up"
  type        = number
  default     = 70
}

variable "cpu_scale_down_threshold" {
  description = "CPU utilization threshold to trigger scale down"
  type        = number
  default     = 30
}

variable "enable_target_tracking" {
  description = "Enable target tracking scaling policy"
  type        = bool
  default     = true
}

variable "target_cpu_utilization" {
  description = "Target CPU utilization for target tracking scaling"
  type        = number
  default     = 50
}

variable "enable_scheduled_scaling" {
  description = "Enable scheduled scaling actions"
  type        = bool
  default     = false
}

# Health check configuration
variable "health_check_grace_period" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 300
}

variable "health_check_type" {
  description = "Health check type (EC2 or ELB)"
  type        = string
  default     = "ELB"
}

# Launch template configuration
variable "enable_instance_metadata_v2" {
  description = "Enable Instance Metadata Service Version 2"
  type        = bool
  default     = true
}

variable "instance_metadata_hop_limit" {
  description = "Instance metadata hop limit"
  type        = number
  default     = 1
}

# Lifecycle configuration
variable "instance_warmup_time" {
  description = "Instance warmup time in seconds"
  type        = number
  default     = 300
}

variable "default_cooldown" {
  description = "Default cooldown period in seconds"
  type        = number
  default     = 300
}

# Termination configuration
variable "termination_policies" {
  description = "List of termination policies"
  type        = list(string)
  default     = ["OldestInstance"]
}

# Logging configuration
variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
}

# Instance refresh configuration
variable "enable_instance_refresh" {
  description = "Enable instance refresh for deployments"
  type        = bool
  default     = true
}

variable "min_healthy_percentage" {
  description = "Minimum healthy percentage during instance refresh"
  type        = number
  default     = 50
}

# Placement configuration
variable "enable_placement_group" {
  description = "Enable placement group for instances"
  type        = bool
  default     = false
}

variable "placement_strategy" {
  description = "Placement group strategy"
  type        = string
  default     = "cluster"
}