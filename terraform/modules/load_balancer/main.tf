# Application Load Balancer
resource "aws_lb" "proxy_lamp_alb" {
  name               = "proxy-lamp-alb-${var.deployment_suffix}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets           = var.public_subnet_ids

  enable_deletion_protection = false  # Set to true for production
  
  # Enable access logs (optional but recommended for production)
  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb-logs"
    enabled = true
  }

  tags = merge(var.tags, {
    Name = "proxy-lamp-alb-${var.deployment_suffix}"
    Type = "Application Load Balancer"
  })
}

# S3 bucket for ALB access logs
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "proxy-lamp-alb-logs-${var.deployment_suffix}-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = merge(var.tags, {
    Name = "proxy-lamp-alb-logs-${var.deployment_suffix}"
    Type = "ALB Access Logs"
  })
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "alb_logs_versioning" {
  bucket = aws_s3_bucket.alb_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs_encryption" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "alb_logs_lifecycle" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "alb_logs_retention"
    status = "Enabled"

    filter {
      prefix = "alb-logs/"
    }

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# S3 bucket policy for ALB access logs
resource "aws_s3_bucket_policy" "alb_logs_policy" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_elb_service_account.main.id}:root"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# Data source for ELB service account
data "aws_elb_service_account" "main" {}

# Target Group for web servers
resource "aws_lb_target_group" "proxy_lamp_tg" {
  name     = "proxy-lamp-tg-${var.deployment_suffix}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  # Health check configuration
  health_check {
    enabled             = true
    healthy_threshold   = var.healthy_threshold
    interval            = var.health_check_interval
    matcher             = "200"
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = var.health_check_timeout
    unhealthy_threshold = var.unhealthy_threshold
  }

  # Stickiness configuration (optional)
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400  # 24 hours
    enabled         = false  # Set to true if you need session persistence
  }

  # Target group attributes
  target_type = "instance"
  
  # Deregistration delay
  deregistration_delay = 30

  tags = merge(var.tags, {
    Name = "proxy-lamp-tg-${var.deployment_suffix}"
    Type = "Target Group"
  })
}

# HTTP Listener (redirects to HTTPS in production)
resource "aws_lb_listener" "proxy_lamp_http" {
  load_balancer_arn = aws_lb.proxy_lamp_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.proxy_lamp_tg.arn
  }

  tags = var.tags
}

# HTTPS Listener (optional - requires SSL certificate)
resource "aws_lb_listener" "proxy_lamp_https" {
  count = var.enable_https ? 1 : 0
  
  load_balancer_arn = aws_lb.proxy_lamp_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.ssl_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.proxy_lamp_tg.arn
  }

  tags = var.tags
}

# CloudWatch alarms for load balancer monitoring
resource "aws_cloudwatch_metric_alarm" "alb_target_response_time" {
  alarm_name          = "proxy-lamp-alb-high-response-time-${var.deployment_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "1.0"
  alarm_description   = "This metric monitors ALB target response time"
  alarm_actions       = [aws_sns_topic.alb_alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.proxy_lamp_alb.arn_suffix
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "proxy-lamp-alb-unhealthy-hosts-${var.deployment_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "This metric monitors unhealthy hosts behind ALB"
  alarm_actions       = [aws_sns_topic.alb_alerts.arn]

  dimensions = {
    TargetGroup  = aws_lb_target_group.proxy_lamp_tg.arn_suffix
    LoadBalancer = aws_lb.proxy_lamp_alb.arn_suffix
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_http_5xx_errors" {
  alarm_name          = "proxy-lamp-alb-5xx-errors-${var.deployment_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors 5XX errors from ALB"
  alarm_actions       = [aws_sns_topic.alb_alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.proxy_lamp_alb.arn_suffix
  }

  tags = var.tags
}

# SNS topic for ALB alerts
resource "aws_sns_topic" "alb_alerts" {
  name = "proxy-lamp-alb-alerts-${var.deployment_suffix}"

  tags = merge(var.tags, {
    Name = "proxy-lamp-alb-alerts-${var.deployment_suffix}"
    Type = "SNS Topic"
  })
}

# WAF Web ACL for additional security (optional)
resource "aws_wafv2_web_acl" "proxy_lamp_waf" {
  count = var.enable_waf ? 1 : 0
  
  name  = "proxy-lamp-waf-${var.deployment_suffix}"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # Rate limiting rule
  rule {
    name     = "RateLimitRule"
    priority = 1

    override_action {
      none {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }

    action {
      block {}
    }
  }

  # AWS Managed Core Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  tags = merge(var.tags, {
    Name = "proxy-lamp-waf-${var.deployment_suffix}"
  })

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "ProxyLampWAF"
    sampled_requests_enabled   = true
  }
}

# Associate WAF with ALB
resource "aws_wafv2_web_acl_association" "proxy_lamp_waf_association" {
  count = var.enable_waf ? 1 : 0
  
  resource_arn = aws_lb.proxy_lamp_alb.arn
  web_acl_arn  = aws_wafv2_web_acl.proxy_lamp_waf[0].arn
}