# terraform/modules/load_balancer/main.tf - FIXED Target Group Configuration

# Target Group for web servers with improved health checks
# Target Group for web servers with improved health checks
resource "aws_lb_target_group" "proxy_lamp_tg" {
  name     = "proxy-lamp-tg-${var.deployment_suffix}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  # FIXED: Improved health check configuration
  health_check {
    enabled             = true
    healthy_threshold   = 2   # FIXED: Quick to mark healthy
    interval            = 30  # FIXED: Check every 30 seconds
    matcher             = "200,404"  # Accept 404 for non-existent paths
    path                = "/"        # FIXED: Use root path instead of /health.php initially
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 10         # FIXED: 10 second timeout
    unhealthy_threshold = 3          # FIXED: 3 consecutive failures before marking unhealthy
  }

  # Stickiness configuration (optional)
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400  # 24 hours
    enabled         = false  # Disabled for better load distribution
  }

  # Target group attributes
  target_type = "instance"
  
  # FIXED: Shorter deregistration delay for faster scaling
  deregistration_delay = 30

  tags = merge(var.tags, {
    Name = "proxy-lamp-tg-${var.deployment_suffix}"
    Type = "Target Group"
  })
}

# Health check configuration
variable "health_check_path" {
  description = "Health check path for load balancer target group"
  type        = string
  default     = "/health.php"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30  # FIXED: Reduced from 60 to 30 seconds
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 10  # FIXED: Reduced from 15 to 10 seconds
}

variable "healthy_threshold" {
  description = "Number of consecutive successful health checks"
  type        = number
  default     = 2  # FIXED: Kept at 2 for faster recovery
}

variable "unhealthy_threshold" {
  description = "Number of consecutive failed health checks"
  type        = number
  default     = 3  # FIXED: Reduced from 5 to 3 for faster detection but not too aggressive
}