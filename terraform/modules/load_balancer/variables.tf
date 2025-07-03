variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs of public subnets for load balancer"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group ID for Application Load Balancer"
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

# Health check configuration
variable "health_check_path" {
  description = "Health check path for load balancer target group"
  type        = string
  default     = "/"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 10
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

# SSL/HTTPS configuration
variable "enable_https" {
  description = "Enable HTTPS listener"
  type        = bool
  default     = false
}

variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate for HTTPS listener"
  type        = string
  default     = ""
}

# WAF configuration
variable "enable_waf" {
  description = "Enable AWS WAF for additional security"
  type        = bool
  default     = false
}

# Access logs configuration
variable "enable_access_logs" {
  description = "Enable ALB access logs"
  type        = bool
  default     = true
}

# Load balancer configuration
variable "load_balancer_type" {
  description = "Type of load balancer"
  type        = string
  default     = "application"
  validation {
    condition     = contains(["application", "network"], var.load_balancer_type)
    error_message = "Load balancer type must be either 'application' or 'network'."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for load balancer"
  type        = bool
  default     = false
}

# Target group configuration
variable "target_group_port" {
  description = "Port for target group"
  type        = number
  default     = 80
}

variable "target_group_protocol" {
  description = "Protocol for target group"
  type        = string
  default     = "HTTP"
}

variable "deregistration_delay" {
  description = "Deregistration delay in seconds"
  type        = number
  default     = 30
}

# Stickiness configuration
variable "enable_stickiness" {
  description = "Enable sticky sessions"
  type        = bool
  default     = false
}

variable "stickiness_duration" {
  description = "Stickiness duration in seconds"
  type        = number
  default     = 86400  # 24 hours
}

# Monitoring and alerting
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for load balancer"
  type        = bool
  default     = true
}

variable "response_time_threshold" {
  description = "Response time threshold for CloudWatch alarm"
  type        = number
  default     = 1.0
}

variable "error_rate_threshold" {
  description = "Error rate threshold for CloudWatch alarm"
  type        = number
  default     = 10
}