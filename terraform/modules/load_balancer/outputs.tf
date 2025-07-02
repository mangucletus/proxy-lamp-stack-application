output "load_balancer_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.proxy_lamp_alb.arn
}

output "load_balancer_arn_suffix" {
  description = "ARN suffix of the Application Load Balancer"
  value       = aws_lb.proxy_lamp_alb.arn_suffix
}

output "load_balancer_dns" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.proxy_lamp_alb.dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.proxy_lamp_alb.zone_id
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.proxy_lamp_tg.arn
}

output "target_group_arn_suffix" {
  description = "ARN suffix of the target group"
  value       = aws_lb_target_group.proxy_lamp_tg.arn_suffix
}

output "target_group_name" {
  description = "Name of the target group"
  value       = aws_lb_target_group.proxy_lamp_tg.name
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener"
  value       = aws_lb_listener.proxy_lamp_http.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener"
  value       = var.enable_https ? aws_lb_listener.proxy_lamp_https[0].arn : ""
}

output "alb_logs_bucket_name" {
  description = "Name of the S3 bucket for ALB access logs"
  value       = aws_s3_bucket.alb_logs.bucket
}

output "alb_logs_bucket_arn" {
  description = "ARN of the S3 bucket for ALB access logs"
  value       = aws_s3_bucket.alb_logs.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for ALB alerts"
  value       = aws_sns_topic.alb_alerts.arn
}

output "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = var.enable_waf ? aws_wafv2_web_acl.proxy_lamp_waf[0].arn : ""
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarm ARNs"
  value = {
    response_time = aws_cloudwatch_metric_alarm.alb_target_response_time.arn
    unhealthy_hosts = aws_cloudwatch_metric_alarm.alb_unhealthy_hosts.arn
    http_5xx_errors = aws_cloudwatch_metric_alarm.alb_http_5xx_errors.arn
  }
}

output "load_balancer_summary" {
  description = "Summary of load balancer configuration"
  value = {
    dns_name         = aws_lb.proxy_lamp_alb.dns_name
    zone_id          = aws_lb.proxy_lamp_alb.zone_id
    target_group     = aws_lb_target_group.proxy_lamp_tg.name
    health_check_path = var.health_check_path
    https_enabled    = var.enable_https
    waf_enabled      = var.enable_waf
    logs_bucket      = aws_s3_bucket.alb_logs.bucket
  }
}