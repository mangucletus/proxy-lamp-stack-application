output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.proxy_lamp_asg.arn
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.proxy_lamp_asg.name
}

output "autoscaling_group_id" {
  description = "ID of the Auto Scaling Group"
  value       = aws_autoscaling_group.proxy_lamp_asg.id
}

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.proxy_lamp_lt.id
}

output "launch_template_arn" {
  description = "ARN of the launch template"
  value       = aws_launch_template.proxy_lamp_lt.arn
}

output "launch_template_latest_version" {
  description = "Latest version of the launch template"
  value       = aws_launch_template.proxy_lamp_lt.latest_version
}

output "key_pair_name" {
  description = "Name of the EC2 key pair"
  value       = aws_key_pair.proxy_lamp_keypair.key_name
}

output "key_pair_id" {
  description = "ID of the EC2 key pair"
  value       = aws_key_pair.proxy_lamp_keypair.key_pair_id
}

output "iam_role_arn" {
  description = "ARN of the IAM role for EC2 instances"
  value       = aws_iam_role.ec2_role.arn
}

output "iam_role_name" {
  description = "Name of the IAM role for EC2 instances"
  value       = aws_iam_role.ec2_role.name
}

output "iam_instance_profile_arn" {
  description = "ARN of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_profile.arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_profile.name
}

# Dynamic outputs - simplified to avoid null issues
output "instance_ids" {
  description = "IDs of EC2 instances in the Auto Scaling Group"
  value       = []  # Will be populated after instances are created
}

output "instance_ips" {
  description = "Public IP addresses of EC2 instances in the Auto Scaling Group"
  value       = []  # Will be populated after instances are created
}

output "instance_private_ips" {
  description = "Private IP addresses of EC2 instances in the Auto Scaling Group"
  value       = []  # Will be populated after instances are created
}

# Auto Scaling Policies
output "scale_up_policy_arn" {
  description = "ARN of the scale up policy"
  value       = aws_autoscaling_policy.scale_up.arn
}

output "scale_down_policy_arn" {
  description = "ARN of the scale down policy"
  value       = aws_autoscaling_policy.scale_down.arn
}

output "target_tracking_policy_arn" {
  description = "ARN of the target tracking policy"
  value       = var.enable_target_tracking ? aws_autoscaling_policy.target_tracking_policy[0].arn : ""
}

# CloudWatch Alarms
output "cpu_high_alarm_arn" {
  description = "ARN of the CPU high alarm"
  value       = aws_cloudwatch_metric_alarm.cpu_high.arn
}

output "cpu_low_alarm_arn" {
  description = "ARN of the CPU low alarm"
  value       = aws_cloudwatch_metric_alarm.cpu_low.arn
}

# CloudWatch Log Group
output "app_log_group_name" {
  description = "Name of the application CloudWatch log group"
  value       = aws_cloudwatch_log_group.app_logs.name
}

output "app_log_group_arn" {
  description = "ARN of the application CloudWatch log group"
  value       = aws_cloudwatch_log_group.app_logs.arn
}

# SNS Topic
output "sns_topic_arn" {
  description = "ARN of the SNS topic for Auto Scaling notifications"
  value       = aws_sns_topic.asg_notifications.arn
}

# Scaling configuration summary
output "scaling_configuration" {
  description = "Auto Scaling Group configuration summary"
  value = {
    min_size                = aws_autoscaling_group.proxy_lamp_asg.min_size
    max_size                = aws_autoscaling_group.proxy_lamp_asg.max_size
    desired_capacity        = aws_autoscaling_group.proxy_lamp_asg.desired_capacity
    health_check_type       = aws_autoscaling_group.proxy_lamp_asg.health_check_type
    health_check_grace_period = aws_autoscaling_group.proxy_lamp_asg.health_check_grace_period
    current_instance_count  = 0  # Will be updated after instances are created
    target_tracking_enabled = var.enable_target_tracking
    scheduled_scaling_enabled = var.enable_scheduled_scaling
  }
}

# Launch template configuration summary
output "launch_template_summary" {
  description = "Launch template configuration summary"
  value = {
    id           = aws_launch_template.proxy_lamp_lt.id
    name         = aws_launch_template.proxy_lamp_lt.name
    version      = aws_launch_template.proxy_lamp_lt.latest_version
    ami_id       = aws_launch_template.proxy_lamp_lt.image_id
    instance_type = aws_launch_template.proxy_lamp_lt.instance_type
    key_name     = aws_launch_template.proxy_lamp_lt.key_name
  }
  sensitive = true
}

# SSH connection commands - simplified
output "ssh_commands" {
  description = "SSH commands to connect to instances"
  value       = ["Instances not yet available - check AWS console for IP addresses"]
}

# Instance health status - simplified to avoid null issues
output "instance_health_summary" {
  description = "Summary of instance health in Auto Scaling Group"
  value = {
    total_instances   = 0
    running_instances = 0
    instance_states   = []
    note             = "Instance data will be available after deployment completes"
  }
}