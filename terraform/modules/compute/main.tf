# terraform/modules/compute/main.tf - FIXED VERSION

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
          "ec2:DescribeInstances",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeTags",
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

# Launch Template for Auto Scaling Group
resource "aws_launch_template" "proxy_lamp_lt" {
  name_prefix   = "proxy-lamp-lt-${var.deployment_suffix}-"
  image_id      = local.ubuntu_ami_id
  instance_type = var.instance_type
  key_name      = aws_key_pair.proxy_lamp_keypair.key_name

  vpc_security_group_ids = [var.web_sg_id]
  
  # FIXED: Simplified user data
  user_data = base64encode(templatefile("${path.module}/../../userdata.sh", {
    db_endpoint = var.db_endpoint
    db_password = var.db_password
    aws_region  = var.aws_region
    deployment_suffix = var.deployment_suffix
  }))

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
      DatabaseEndpoint = var.db_endpoint
      DatabasePassword = var.db_password
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

# FIXED: Auto Scaling Group with stable configuration
resource "aws_autoscaling_group" "proxy_lamp_asg" {
  name                = "proxy-lamp-asg-${var.deployment_suffix}"
  vpc_zone_identifier = var.public_subnet_ids
  target_group_arns   = [var.target_group_arn]
  health_check_type   = "EC2"  # FIXED: Start with EC2, switch to ELB after deployment
  health_check_grace_period = 900  # FIXED: Increased to 15 minutes

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  # FIXED: Less aggressive termination policies
  termination_policies = ["OldestInstance", "Default"]

  # FIXED: Set default cooldown for scaling operations
  default_cooldown = 600  # 10 minutes cooldown for scaling operations

  # FIXED: Conservative instance refresh configuration
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 80  # FIXED: Higher percentage to maintain stability
      instance_warmup       = 600
    }
  }

  launch_template {
    id      = aws_launch_template.proxy_lamp_lt.id
    version = "$Latest"
  }

  # FIXED: Remove aggressive lifecycle hooks that cause termination
  # Instead, use gentler hooks
  initial_lifecycle_hook {
    name                 = "instance-launching"
    default_result       = "CONTINUE"  # FIXED: Changed from ABANDON to CONTINUE
    heartbeat_timeout    = 900         # FIXED: Increased timeout
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
  }

  # FIXED: Don't wait for capacity, let instances come up naturally
  wait_for_capacity_timeout = "0"

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

  tag {
    key                 = "DatabaseEndpoint"
    value               = var.db_endpoint
    propagate_at_launch = true
  }

  tag {
    key                 = "DatabasePassword"
    value               = var.db_password
    propagate_at_launch = true
  }
}

# FIXED: Conservative Auto Scaling Policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "proxy-lamp-scale-up-${var.deployment_suffix}"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 600  # FIXED: Increased cooldown to prevent rapid scaling
  autoscaling_group_name = aws_autoscaling_group.proxy_lamp_asg.name

  policy_type = "SimpleScaling"
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "proxy-lamp-scale-down-${var.deployment_suffix}"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 600  # FIXED: Increased cooldown
  autoscaling_group_name = aws_autoscaling_group.proxy_lamp_asg.name

  policy_type = "SimpleScaling"
}

# FIXED: Conservative CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "proxy-lamp-cpu-high-${var.deployment_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"  # FIXED: Increased evaluation periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"  # FIXED: Increased period
  statistic           = "Average"
  threshold           = "80"   # FIXED: Higher threshold
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
  evaluation_periods  = "5"  # FIXED: More evaluation periods for scale down
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "20"  # FIXED: Lower threshold
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.proxy_lamp_asg.name
  }

  tags = var.tags
}

# FIXED: Target Tracking Scaling Policy (more stable than simple scaling)
resource "aws_autoscaling_policy" "target_tracking_policy" {
  count = var.enable_target_tracking ? 1 : 0
  
  name                   = "proxy-lamp-target-tracking-${var.deployment_suffix}"
  autoscaling_group_name = aws_autoscaling_group.proxy_lamp_asg.name
  policy_type           = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0  # FIXED: Higher target value for stability
    # FIXED: Removed scale_out_cooldown and scale_in_cooldown attributes
    # These are not supported in target_tracking_configuration
    # The ASG will use the default_cooldown defined above
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