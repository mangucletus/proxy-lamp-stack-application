# terraform/modules/compute/variables.tf - CLEAN VERSION

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "AWS key pair name"
  type        = string
  default     = "proxy-lamp-keypair"
}

variable "public_key" {
  description = "Public key for EC2 access"
  type        = string
  sensitive   = true
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

variable "cpu_scale_up_threshold" {
  description = "CPU utilization threshold to trigger scale up"
  type        = number
  default     = 80
}

variable "cpu_scale_down_threshold" {
  description = "CPU utilization threshold to trigger scale down"
  type        = number
  default     = 20
}

variable "enable_target_tracking" {
  description = "Enable target tracking scaling policy"
  type        = bool
  default     = true
}

variable "target_cpu_utilization" {
  description = "Target CPU utilization for target tracking scaling"
  type        = number
  default     = 60
}

variable "enable_scheduled_scaling" {
  description = "Enable scheduled scaling actions"
  type        = bool
  default     = false
}

variable "health_check_grace_period" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 900
}

variable "health_check_type" {
  description = "Health check type (EC2 or ELB)"
  type        = string
  default     = "EC2"
}

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

variable "instance_warmup_time" {
  description = "Instance warmup time in seconds"
  type        = number
  default     = 600
}

variable "default_cooldown" {
  description = "Default cooldown period in seconds"
  type        = number
  default     = 600
}

variable "termination_policies" {
  description = "List of termination policies"
  type        = list(string)
  default     = ["OldestInstance", "Default"]
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
}

variable "enable_instance_refresh" {
  description = "Enable instance refresh for deployments"
  type        = bool
  default     = true
}

variable "min_healthy_percentage" {
  description = "Minimum healthy percentage during instance refresh"
  type        = number
  default     = 80
}

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