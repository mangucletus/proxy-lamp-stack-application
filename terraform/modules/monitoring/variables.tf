variable "load_balancer_arn_suffix" {
  description = "ARN suffix of the Application Load Balancer"
  type        = string
}

variable "target_group_arn_suffix" {
  description = "ARN suffix of the Target Group"
  type        = string
}

variable "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  type        = string
}

variable "db_instance_identifier" {
  description = "RDS database instance identifier"
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

# CloudWatch configuration
variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

# Alarm thresholds
variable "response_time_threshold" {
  description = "Response time threshold for alarms (seconds)"
  type        = number
  default     = 2.0
}

variable "error_rate_threshold" {
  description = "Error rate threshold for alarms"
  type        = number
  default     = 10
}

variable "cpu_threshold" {
  description = "CPU utilization threshold for database alarms (%)"
  type        = number
  default     = 80
}

variable "healthy_host_threshold" {
  description = "Minimum healthy host count threshold"
  type        = number
  default     = 1
}

# Alert configuration
variable "enable_email_alerts" {
  description = "Enable email alerts via SNS"
  type        = bool
  default     = false
}

variable "alert_email_endpoints" {
  description = "List of email addresses for alerts"
  type        = list(string)
  default     = []
}

variable "enable_slack_alerts" {
  description = "Enable Slack alerts via SNS"
  type        = bool
  default     = false
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for alerts"
  type        = string
  default     = ""
  sensitive   = true
}

# Application Insights configuration
variable "enable_application_insights" {
  description = "Enable AWS Application Insights"
  type        = bool
  default     = true
}

variable "auto_config_enabled" {
  description = "Enable automatic configuration for Application Insights"
  type        = bool
  default     = true
}

# Anomaly detection configuration
variable "enable_anomaly_detection" {
  description = "Enable CloudWatch anomaly detection"
  type        = bool
  default     = true
}

variable "anomaly_evaluation_periods" {
  description = "Number of evaluation periods for anomaly detection"
  type        = number
  default     = 2
}

# Dashboard configuration
variable "dashboard_refresh_interval" {
  description = "Dashboard refresh interval in seconds"
  type        = number
  default     = 300
}

variable "enable_custom_metrics" {
  description = "Enable custom application metrics"
  type        = bool
  default     = true
}

# Log analysis configuration
variable "enable_log_insights" {
  description = "Enable CloudWatch Logs Insights queries"
  type        = bool
  default     = true
}

variable "log_insights_retention_days" {
  description = "Retention period for Logs Insights queries"
  type        = number
  default     = 30
}

# Performance monitoring
variable "enable_performance_monitoring" {
  description = "Enable enhanced performance monitoring"
  type        = bool
  default     = true
}

variable "performance_metric_period" {
  description = "Period for performance metrics in seconds"
  type        = number
  default     = 300
}

# Composite alarm configuration
variable "enable_composite_alarms" {
  description = "Enable composite alarms for application health"
  type        = bool
  default     = true
}

# Metric filter configuration
variable "enable_metric_filters" {
  description = "Enable CloudWatch metric filters"
  type        = bool
  default     = true
}

variable "error_pattern" {
  description = "Log pattern for error detection"
  type        = string
  default     = "ERROR"
}

variable "warning_pattern" {
  description = "Log pattern for warning detection"
  type        = string
  default     = "WARN"
}