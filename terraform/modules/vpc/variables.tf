# Define the AWS region to deploy resources in
variable "aws_region" {
  description = "AWS region"      # A short description for documentation
  type        = string            # The type must be a string
  default     = "eu-central-1"    # Updated region (Frankfurt)
}

# Deployment suffix for unique naming
variable "deployment_suffix" {
  description = "Unique suffix for resource naming to avoid conflicts"
  type        = string
}

# Common tags to apply to all resources
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# VPC CIDR block
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# Public subnet CIDR blocks
variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

# Private subnet CIDR blocks
variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

# Enable NAT gateways for private subnets
variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

# Enable VPC flow logs
variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}

# Flow logs retention period
variable "flow_logs_retention_days" {
  description = "Retention period for VPC Flow Logs in days"
  type        = number
  default     = 14
}