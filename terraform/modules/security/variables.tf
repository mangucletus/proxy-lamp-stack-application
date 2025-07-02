variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
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

# Public subnet IDs for Network ACLs
variable "public_subnet_ids" {
  description = "IDs of public subnets for Network ACLs"
  type        = list(string)
  default     = []
}

# Private subnet IDs for Network ACLs
variable "private_subnet_ids" {
  description = "IDs of private subnets for Network ACLs"
  type        = list(string)
  default     = []
}

# SSH access CIDR blocks (restrict in production)
variable "ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Change to your IP in production
}

# Database access configuration
variable "database_port" {
  description = "Database port number"
  type        = number
  default     = 3306
}

# Monitoring port configuration
variable "monitoring_port" {
  description = "Port for monitoring endpoints"
  type        = number
  default     = 8080
}

# Enable additional security features
variable "enable_network_acls" {
  description = "Enable Network ACLs for additional security"
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs for security monitoring"
  type        = bool
  default     = true
}