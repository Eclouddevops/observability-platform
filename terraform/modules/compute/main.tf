###############################################################################
# Module: compute
#
# Flow:
#   1. IAM Role  → EC2 can call SSM, CloudWatch, Secrets Manager
#   2. user_data → installs Nginx + static website on every new instance
#   3. Launch Template → references IAM profile + user_data + SG
#   4. ASG → desired=1, min=1, max=8 → attached to ALB target group
#   5. Step Scaling (CPU + Memory):
#        >= 70%  →  +1 instance
#        >= 80%  →  +2 instances
#        >= 90%  →  +4 instances  (toward max 8)
#        <= 20%  →  -1 instance
#   6. ALB target group health check hits /health on port 80
#      When ASG scales out → new instance starts → Nginx starts →
#      ALB detects /health 200 → routes traffic → website is live
###############################################################################

# ── IAM Role ──────────────────────────────────────────────────────────────────
resource "aws_iam_role" "ec2" {
  name = "${var.env_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.common_tags, { Name = "${var.env_name}-ec2-role" })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "secret" {
  role       = aws_iam_role.ec2.name
  policy_arn = var.read_secret_policy_arn
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.env_name}-ec2-profile"
  role = aws_iam_role.ec2.name
  tags = var.common_tags
}

# ── Latest Amazon Linux 2023 AMI ──────────────────────────────────────────────
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-kernel-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

# ── Launch Template ───────────────────────────────────────────────────────────
# Every instance launched from this template will:
#   1. Install Nginx
#   2. Write the static HTML website
#   3. Install + start CloudWatch agent (for memory metrics)
#   4. Expose /health and /info endpoints
#   5. Register itself with ALB via ASG target group attachment
resource "aws_launch_template" "this" {
  name          = "${var.env_name}-lt"
  image_id      = var.ami_id != "" ? var.ami_id : data.aws_ami.al2023.id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  # Private subnet — no public IP
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.ec2_sg_id]
    delete_on_termination       = true
  }

  # IMDSv2 enforced (security best practice)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring { enabled = true }

  # 30 GB — minimum required by AL2023 AMI snapshot
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # ── user_data — runs once on every new EC2 instance ──────────────────────
  user_data = base64encode(templatefile("${path.module}/website.sh.tpl", {
    env_name       = var.env_name
    environment    = var.environment
    aws_region     = var.aws_region
    db_secret_name = var.db_secret_name
    app_port       = var.app_port
  }))

  # Tag every instance launched from this template
  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags, {
      Name        = "${var.env_name}-ec2"
      Environment = var.environment
      Role        = "web"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.common_tags, {
      Name        = "${var.env_name}-ec2-vol"
      Environment = var.environment
    })
  }

  tags = merge(var.common_tags, { Name = "${var.env_name}-lt" })

  lifecycle { create_before_destroy = true }
}

# ── Auto Scaling Group ────────────────────────────────────────────────────────
# Starts with 1 instance, scales up to 8 based on CPU/Memory
# Automatically registers new instances with the ALB target group
resource "aws_autoscaling_group" "this" {
  name                = "${var.env_name}-asg"
  desired_capacity    = var.asg_desired
  min_size            = var.asg_min
  max_size            = var.asg_max
  vpc_zone_identifier = var.private_subnet_ids

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  # ALB target group — ASG auto-registers/deregisters instances
  # NLB target group — also attached for TCP-level access
  target_group_arns = [
    var.alb_target_group_arn,
    var.nlb_target_group_arn,
  ]

  # ELB health check — ALB pings /health on port 80
  # If instance fails health check → ASG terminates and replaces it
  health_check_type         = "ELB"
  health_check_grace_period = 300

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceCapacity",
    "GroupPendingCapacity",
    "GroupTerminatingCapacity",
    "GroupTotalCapacity",
    "GroupMinSize",
    "GroupMaxSize",
  ]

  # Rolling updates — replace instances one by one when LT changes
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 120
    }
  }

  # Propagate all tags to instances
  dynamic "tag" {
    for_each = merge(var.common_tags, {
      Name        = "${var.env_name}-ec2"
      Environment = var.environment
      Role        = "web"
    })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

###############################################################################
# Step Scaling — Scale OUT
# One policy handles all three thresholds (70 / 80 / 90 %)
#
#  Breach threshold = 70 (alarm fires at >= 70)
#  step_adjustment metric_interval = distance above 70
#    0  to 10  → CPU 70–80%  → +1
#    10 to 20  → CPU 80–90%  → +2
#    20+       → CPU >= 90%  → +4
###############################################################################
resource "aws_autoscaling_policy" "scale_out" {
  name                      = "${var.env_name}-scale-out"
  autoscaling_group_name    = aws_autoscaling_group.this.name
  policy_type               = "StepScaling"
  adjustment_type           = "ChangeInCapacity"
  estimated_instance_warmup = 120

  # 70–80% → add 1
  step_adjustment {
    metric_interval_lower_bound = 0
    metric_interval_upper_bound = 10
    scaling_adjustment          = 1
  }

  # 80–90% → add 2
  step_adjustment {
    metric_interval_lower_bound = 10
    metric_interval_upper_bound = 20
    scaling_adjustment          = 2
  }

  # 90%+ → add 4 (rushes toward max=8)
  step_adjustment {
    metric_interval_lower_bound = 20
    scaling_adjustment          = 4
  }
}

###############################################################################
# Step Scaling — Scale IN
###############################################################################
resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.env_name}-scale-in"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

###############################################################################
# CloudWatch Alarms — CPU
###############################################################################
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.env_name}-cpu-high-70"
  alarm_description   = "CPU >= 70% — step scale out (+1 / +2 / +4)"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.this.name }
  tags                = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.env_name}-cpu-low-20"
  alarm_description   = "CPU <= 20% — scale in (-1)"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 20
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.this.name }
  tags                = var.common_tags
}

###############################################################################
# CloudWatch Alarms — Memory (requires CloudWatch Agent on instances)
###############################################################################
resource "aws_cloudwatch_metric_alarm" "mem_high" {
  alarm_name          = "${var.env_name}-mem-high-70"
  alarm_description   = "Memory >= 70% — step scale out (+1 / +2 / +4)"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.this.name }
  tags                = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "mem_low" {
  alarm_name          = "${var.env_name}-mem-low-20"
  alarm_description   = "Memory <= 20% — scale in (-1)"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period              = 120
  statistic           = "Average"
  threshold           = 20
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.this.name }
  tags                = var.common_tags
}
