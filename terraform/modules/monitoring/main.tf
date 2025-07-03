# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "proxy_lamp_dashboard" {
  dashboard_name = "ProxyLAMP-Dashboard-${var.deployment_suffix}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.load_balancer_arn_suffix],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.load_balancer_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", var.load_balancer_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", var.load_balancer_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.load_balancer_arn_suffix]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Load Balancer Metrics"
          period  = 300
          stat    = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", var.target_group_arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", var.target_group_arn_suffix]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Target Group Health"
          period  = 300
          stat    = "Average"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/AutoScaling", "GroupMinSize", "AutoScalingGroupName", var.autoscaling_group_name],
            ["AWS/AutoScaling", "GroupMaxSize", "AutoScalingGroupName", var.autoscaling_group_name],
            ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", var.autoscaling_group_name],
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", var.autoscaling_group_name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Auto Scaling Group Metrics"
          period  = 300
          stat    = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_identifier],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_instance_identifier],
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.db_instance_identifier]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "RDS Database Metrics"
          period  = 300
          stat    = "Average"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 24
        height = 6

        properties = {
          query   = "SOURCE '/aws/ec2/proxy-lamp/apache/access'\n| fields @timestamp, @message\n| filter @message like /ERROR/\n| sort @timestamp desc\n| limit 100"
          region  = data.aws_region.current.name
          title   = "Recent Apache Errors"
          view    = "table"
        }
      }
    ]
  })
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "apache_access_logs" {
  name              = "/aws/ec2/proxy-lamp/apache/access"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "proxy-lamp-apache-access-logs"
    Type = "Apache Access Logs"
  })
}

resource "aws_cloudwatch_log_group" "apache_error_logs" {
  name              = "/aws/ec2/proxy-lamp/apache/error"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "proxy-lamp-apache-error-logs"
    Type = "Apache Error Logs"
  })
}

resource "aws_cloudwatch_log_group" "cloud_init_logs" {
  name              = "/aws/ec2/proxy-lamp/cloud-init"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "proxy-lamp-cloud-init-logs"
    Type = "Cloud Init Logs"
  })
}

# Custom Metrics for Application Performance
resource "aws_cloudwatch_metric_alarm" "high_response_time" {
  alarm_name          = "proxy-lamp-high-response-time-${var.deployment_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "2.0"
  alarm_description   = "This metric monitors ALB response time"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = var.load_balancer_arn_suffix
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "proxy-lamp-high-error-rate-${var.deployment_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors 5XX error rate"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.load_balancer_arn_suffix
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_cpu_high" {
  alarm_name          = "proxy-lamp-db-cpu-high-${var.deployment_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "low_healthy_hosts" {
  alarm_name          = "proxy-lamp-low-healthy-hosts-${var.deployment_suffix}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors healthy host count"
  alarm_actions       = [aws_sns_topic.critical_alerts.arn]

  dimensions = {
    TargetGroup  = var.target_group_arn_suffix
    LoadBalancer = var.load_balancer_arn_suffix
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "high_request_count" {
  alarm_name          = "proxy-lamp-high-request-count-${var.deployment_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1000"
  alarm_description   = "This metric monitors high request count patterns"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = var.load_balancer_arn_suffix
  }

  tags = var.tags
}

# SNS Topics for Alerts
resource "aws_sns_topic" "alerts" {
  name = "proxy-lamp-alerts-${var.deployment_suffix}"

  tags = merge(var.tags, {
    Name = "proxy-lamp-alerts-${var.deployment_suffix}"
    Type = "General Alerts"
  })
}

resource "aws_sns_topic" "critical_alerts" {
  name = "proxy-lamp-critical-alerts-${var.deployment_suffix}"

  tags = merge(var.tags, {
    Name = "proxy-lamp-critical-alerts-${var.deployment_suffix}"
    Type = "Critical Alerts"
  })
}

# CloudWatch Composite Alarms
resource "aws_cloudwatch_composite_alarm" "application_health" {
  alarm_name          = "proxy-lamp-application-health-${var.deployment_suffix}"
  alarm_description   = "Composite alarm for overall application health"
  alarm_actions       = [aws_sns_topic.critical_alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  alarm_rule = join(" OR ", [
    "ALARM(${aws_cloudwatch_metric_alarm.high_response_time.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.high_error_rate.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.low_healthy_hosts.alarm_name})"
  ])

  tags = var.tags
}

# CloudWatch Logs Insights Queries
resource "aws_cloudwatch_query_definition" "error_analysis" {
  name = "proxy-lamp-error-analysis-${var.deployment_suffix}"

  log_group_names = [
    aws_cloudwatch_log_group.apache_error_logs.name
  ]

  query_string = <<EOF
fields @timestamp, @message
| filter @message like /ERROR/
| stats count() by bin(5m)
| sort @timestamp desc
EOF
}

resource "aws_cloudwatch_query_definition" "top_pages" {
  name = "proxy-lamp-top-pages-${var.deployment_suffix}"

  log_group_names = [
    aws_cloudwatch_log_group.apache_access_logs.name
  ]

  query_string = <<EOF
fields @timestamp, @message
| parse @message /(?<ip>\S+) \S+ \S+ \[(?<timestamp>[^\]]+)\] "(?<method>\S+) (?<url>\S+) \S+" (?<status>\d+) (?<size>\S+)/
| filter status = "200"
| stats count() as requests by url
| sort requests desc
| limit 10
EOF
}

resource "aws_cloudwatch_query_definition" "response_time_analysis" {
  name = "proxy-lamp-response-time-analysis-${var.deployment_suffix}"

  log_group_names = [
    aws_cloudwatch_log_group.apache_access_logs.name
  ]

  query_string = <<EOF
fields @timestamp, @message
| parse @message /(?<ip>\S+) \S+ \S+ \[(?<timestamp>[^\]]+)\] "(?<method>\S+) (?<url>\S+) \S+" (?<status>\d+) (?<size>\S+) "(?<referer>[^"]*)" "(?<user_agent>[^"]*)" (?<response_time>\d+)/
| filter ispresent(response_time)
| stats avg(response_time), max(response_time), min(response_time) by bin(5m)
| sort @timestamp desc
EOF
}

# Custom CloudWatch Metrics Namespace
resource "aws_cloudwatch_log_metric_filter" "error_count" {
  name           = "proxy-lamp-error-count-${var.deployment_suffix}"
  log_group_name = aws_cloudwatch_log_group.apache_error_logs.name
  pattern        = "ERROR"

  metric_transformation {
    name      = "ErrorCount"
    namespace = "ProxyLAMP/Application"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "warning_count" {
  name           = "proxy-lamp-warning-count-${var.deployment_suffix}"
  log_group_name = aws_cloudwatch_log_group.apache_error_logs.name
  pattern        = "WARN"

  metric_transformation {
    name      = "WarningCount"
    namespace = "ProxyLAMP/Application"
    value     = "1"
  }
}

# Data source for current region
data "aws_region" "current" {}

# Data source for AWS account ID
data "aws_caller_identity" "current" {}