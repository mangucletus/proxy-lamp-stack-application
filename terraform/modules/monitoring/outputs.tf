output "dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.proxy_lamp_dashboard.dashboard_name}"
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.proxy_lamp_dashboard.dashboard_name
}

output "dashboard_arn" {
  description = "ARN of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.proxy_lamp_dashboard.dashboard_arn
}

# CloudWatch Log Groups
output "log_group_names" {
  description = "Names of CloudWatch log groups"
  value = {
    apache_access = aws_cloudwatch_log_group.apache_access_logs.name
    apache_error  = aws_cloudwatch_log_group.apache_error_logs.name
    cloud_init    = aws_cloudwatch_log_group.cloud_init_logs.name
  }
}

output "log_group_arns" {
  description = "ARNs of CloudWatch log groups"
  value = {
    apache_access = aws_cloudwatch_log_group.apache_access_logs.arn
    apache_error  = aws_cloudwatch_log_group.apache_error_logs.arn
    cloud_init    = aws_cloudwatch_log_group.cloud_init_logs.arn
  }
}

# SNS Topics
output "alerts_topic_arn" {
  description = "ARN of the general alerts SNS topic"
  value       = aws_sns_topic.alerts.arn
}

output "critical_alerts_topic_arn" {
  description = "ARN of the critical alerts SNS topic"
  value       = aws_sns_topic.critical_alerts.arn
}

output "alerts_topic_name" {
  description = "Name of the general alerts SNS topic"
  value       = aws_sns_topic.alerts.name
}

output "critical_alerts_topic_name" {
  description = "Name of the critical alerts SNS topic"
  value       = aws_sns_topic.critical_alerts.name
}

# CloudWatch Alarms
output "cloudwatch_alarms" {
  description = "CloudWatch alarm ARNs"
  value = {
    high_response_time  = aws_cloudwatch_metric_alarm.high_response_time.arn
    high_error_rate     = aws_cloudwatch_metric_alarm.high_error_rate.arn
    database_cpu_high   = aws_cloudwatch_metric_alarm.database_cpu_high.arn
    low_healthy_hosts   = aws_cloudwatch_metric_alarm.low_healthy_hosts.arn
    application_health  = aws_cloudwatch_composite_alarm.application_health.arn
  }
}

# CloudWatch Logs Insights Queries
output "logs_insights_queries" {
  description = "CloudWatch Logs Insights query names"
  value = {
    error_analysis        = aws_cloudwatch_query_definition.error_analysis.name
    top_pages            = aws_cloudwatch_query_definition.top_pages.name
    response_time_analysis = aws_cloudwatch_query_definition.response_time_analysis.name
  }
}

# Metric Filters
output "metric_filters" {
  description = "CloudWatch metric filter names"
  value = {
    error_count   = aws_cloudwatch_log_metric_filter.error_count.name
    warning_count = aws_cloudwatch_log_metric_filter.warning_count.name
  }
}

# Monitoring URLs
output "monitoring_urls" {
  description = "URLs for monitoring resources"
  value = {
    dashboard = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.proxy_lamp_dashboard.dashboard_name}"
    logs      = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:logs-insights"
    alarms    = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#alarmsV2:alarms"
  }
}

# Summary of monitoring configuration
output "monitoring_summary" {
  description = "Summary of monitoring configuration"
  value = {
    dashboard_name        = aws_cloudwatch_dashboard.proxy_lamp_dashboard.dashboard_name
    log_groups_count      = 3
    alarms_count          = 5
    sns_topics_count      = 2
    metric_filters_count  = 2
    logs_insights_queries = 3
    application_insights_enabled = false
    region               = data.aws_region.current.name
    account_id           = data.aws_caller_identity.current.account_id
  }
}

# Alert configuration summary
output "alert_configuration" {
  description = "Alert configuration summary"
  value = {
    general_alerts_topic    = aws_sns_topic.alerts.arn
    critical_alerts_topic   = aws_sns_topic.critical_alerts.arn
    response_time_threshold = var.response_time_threshold
    error_rate_threshold    = var.error_rate_threshold
    cpu_threshold          = var.cpu_threshold
    healthy_host_threshold = var.healthy_host_threshold
  }
}