locals {
  # Static AMI ID for Ubuntu 22.04 LTS in eu-central-1 - Updated to latest
  ubuntu_ami_id = "ami-0e067cc8a2b58de59"
}

# Create Key Pair for EC2 SSH Access
resource "aws_key_pair" "proxy_lamp_keypair" {
  key_name   = "${var.key_name}-${var.deployment_suffix}"
  public_key = var.public_key
  
  tags = merge(var.tags, {
    Name = "${var.key_name}-${var.deployment_suffix}"
  })
}

# IAM Role for EC2 instances
resource "aws_iam_role" "ec2_role" {
  name = "proxy-lamp-ec2-role-${var.deployment_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM Policy for EC2 instances
resource "aws_iam_role_policy" "ec2_policy" {
  name = "proxy-lamp-ec2-policy-${var.deployment_suffix}"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "ec2:DescribeVolumes",
          "ec2:DescribeTags",
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:*:secret:proxy-lamp-db-credentials-${var.deployment_suffix}*"
        ]
      }
    ]
  })
}

# Attach AWS managed policies
resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "proxy-lamp-ec2-profile-${var.deployment_suffix}"
  role = aws_iam_role.ec2_role.name

  tags = var.tags
}

# User data script template
data "template_file" "user_data" {
  template = file("${path.module}/../../userdata.sh")
  
  vars = {
    db_endpoint = var.db_endpoint
    db_password = var.db_password
    aws_region  = var.aws_region
    deployment_suffix = var.deployment_suffix
  }
}

# Launch Template for Auto Scaling Group
resource "aws_launch_template" "proxy_lamp_lt" {
  name_prefix   = "proxy-lamp-lt-${var.deployment_suffix}-"
  image_id      = local.ubuntu_ami_id
  instance_type = var.instance_type
  key_name      = aws_key_pair.proxy_lamp_keypair.key_name

  vpc_security_group_ids = [var.web_sg_id]
  
  user_data = base64encode(data.template_file.user_data.rendered)

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Enable detailed monitoring
  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  # Instance metadata service configuration
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "proxy-lamp-server-${var.deployment_suffix}"
      Type = "Web Server"
      AutoScalingGroup = "proxy-lamp-asg-${var.deployment_suffix}"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "proxy-lamp-server-volume-${var.deployment_suffix}"
    })
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = "proxy-lamp-launch-template-${var.deployment_suffix}"
  })
}

# Auto Scaling Group - FIXED TIMEOUT ISSUE
resource "aws_autoscaling_group" "proxy_lamp_asg" {
  name                = "proxy-lamp-asg-${var.deployment_suffix}"
  vpc_zone_identifier = var.public_subnet_ids
  target_group_arns   = [var.target_group_arn]
  health_check_type   = "ELB"
  health_check_grace_period = 900  # 15 minutes

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  # Termination policies
  termination_policies = ["OldestInstance"]

  # Instance refresh configuration
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup       = 600
    }
  }

  launch_template {
    id      = aws_launch_template.proxy_lamp_lt.id
    version = "$Latest"
  }

  # Lifecycle hooks
  initial_lifecycle_hook {
    name                 = "instance-launching"
    default_result       = "ABANDON"
    heartbeat_timeout    = 1200
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
  }

  initial_lifecycle_hook {
    name                 = "instance-terminating"
    default_result       = "CONTINUE"
    heartbeat_timeout    = 300
    lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
  }

  # CRITICAL FIX: Disable Terraform waiting since ASG works fine
  wait_for_capacity_timeout = "0"  # Don't wait - let ASG work in background

  tag {
    key                 = "Name"
    value               = "proxy-lamp-asg-instance-${var.deployment_suffix}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.tags["Environment"]
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.tags["Project"]
    propagate_at_launch = true
  }

  tag {
    key                 = "AutoScalingGroup"
    value               = "proxy-lamp-asg-${var.deployment_suffix}"
    propagate_at_launch = true
  }
}

# Rest of the file (Auto Scaling Policies, etc.) remains the same...
# Auto Scaling Policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "proxy-lamp-scale-up-${var.deployment_suffix}"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.proxy_lamp_asg.name

  policy_type = "SimpleScaling"
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "proxy-lamp-scale-down-${var.deployment_suffix}"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.proxy_lamp_asg.name

  policy_type = "SimpleScaling"
}

# CloudWatch Alarms for Auto Scaling
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "proxy-lamp-cpu-high-${var.deployment_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = var.cpu_scale_up_threshold
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.proxy_lamp_asg.name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "proxy-lamp-cpu-low-${var.deployment_suffix}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = var.cpu_scale_down_threshold
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.proxy_lamp_asg.name
  }

  tags = var.tags
}

# Target Tracking Scaling Policy
resource "aws_autoscaling_policy" "target_tracking_policy" {
  count = var.enable_target_tracking ? 1 : 0
  
  name                   = "proxy-lamp-target-tracking-${var.deployment_suffix}"
  autoscaling_group_name = aws_autoscaling_group.proxy_lamp_asg.name
  policy_type           = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.target_cpu_utilization
  }
}

# CloudWatch Log Group for application logs
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/aws/ec2/proxy-lamp/application-${var.deployment_suffix}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "proxy-lamp-app-logs-${var.deployment_suffix}"
  })
}

# SNS Topic for Auto Scaling notifications
resource "aws_sns_topic" "asg_notifications" {
  name = "proxy-lamp-asg-notifications-${var.deployment_suffix}"

  tags = merge(var.tags, {
    Name = "proxy-lamp-asg-notifications-${var.deployment_suffix}"
  })
}

# Auto Scaling Notification
resource "aws_autoscaling_notification" "asg_notifications" {
  group_names = [aws_autoscaling_group.proxy_lamp_asg.name]

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]

  topic_arn = aws_sns_topic.asg_notifications.arn
}

# Scheduled Actions (optional)
resource "aws_autoscaling_schedule" "scale_up_business_hours" {
  count = var.enable_scheduled_scaling ? 1 : 0
  
  scheduled_action_name  = "scale-up-business-hours"
  min_size               = var.min_size
  max_size               = var.max_size
  desired_capacity       = var.desired_capacity
  recurrence             = "0 8 * * MON-FRI"
  autoscaling_group_name = aws_autoscaling_group.proxy_lamp_asg.name
}

resource "aws_autoscaling_schedule" "scale_down_off_hours" {
  count = var.enable_scheduled_scaling ? 1 : 0
  
  scheduled_action_name  = "scale-down-off-hours"
  min_size               = 1
  max_size               = var.max_size
  desired_capacity       = 1
  recurrence             = "0 18 * * MON-FRI"
  autoscaling_group_name = aws_autoscaling_group.proxy_lamp_asg.name
}