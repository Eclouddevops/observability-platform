###############################################################################
# Module: compute
# Provisions:
#   - IAM Role + Instance Profile for EC2 (SSM, CloudWatch, Secrets Manager)
#   - Launch Template
#   - Auto Scaling Group (desired 4, min 2, max 8)
#   - ASG attachment to both ALB and NLB target groups
#   - CloudWatch alarms for scale-out / scale-in
###############################################################################

locals {
  name_prefix = "${var.project}-${var.environment}"
}

###############################################################################
# IAM Role for EC2 Instances
###############################################################################
resource "aws_iam_role" "ec2" {
  name = "${local.name_prefix}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-ec2-role"
    Environment = var.environment
  })
}

# Managed policies
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Attach the scoped Secrets Manager read policy from the secrets module
resource "aws_iam_role_policy_attachment" "read_secret" {
  role       = aws_iam_role.ec2.name
  policy_arn = var.read_secret_policy_arn
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name
  tags = var.common_tags
}

###############################################################################
# Fetch latest Amazon Linux 2023 AMI
###############################################################################
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

###############################################################################
# Launch Template
###############################################################################
resource "aws_launch_template" "this" {
  name_prefix   = "${local.name_prefix}-lt-"
  image_id      = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  vpc_security_group_ids = [var.ec2_sg_id]

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"   # enforce IMDSv2
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    environment    = var.environment
    db_secret_name = var.db_secret_name
    aws_region     = var.aws_region
    project        = var.project
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags, {
      Name        = "${local.name_prefix}-ec2"
      Environment = var.environment
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.common_tags, {
      Name        = "${local.name_prefix}-ec2-vol"
      Environment = var.environment
    })
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-lt"
    Environment = var.environment
  })
}

###############################################################################
# Auto Scaling Group
###############################################################################
resource "aws_autoscaling_group" "this" {
  name                = "${local.name_prefix}-asg"
  desired_capacity    = var.asg_desired_capacity
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  vpc_zone_identifier = var.private_subnet_ids

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  # Attach to both ALB and NLB target groups
  target_group_arns = concat(
    [var.alb_target_group_arn],
    var.nlb_target_group_arn != "" ? [var.nlb_target_group_arn] : []
  )

  health_check_type         = "ELB"
  health_check_grace_period = 120

  # Instance Refresh for rolling updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 120
    }
  }

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceCapacity",
    "GroupPendingCapacity",
    "GroupStandbyCapacity",
    "GroupTerminatingCapacity",
    "GroupTotalCapacity"
  ]

  dynamic "tag" {
    for_each = merge(var.common_tags, {
      Name        = "${local.name_prefix}-asg-instance"
      Environment = var.environment
    })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]   # allow external scaling without drift
  }
}

###############################################################################
# Auto Scaling Policies (CPU-based)
###############################################################################
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${local.name_prefix}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.this.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
  policy_type            = "SimpleScaling"
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${local.name_prefix}-scale-in"
  autoscaling_group_name = aws_autoscaling_group.this.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
  policy_type            = "SimpleScaling"
}

###############################################################################
# CloudWatch Alarms for ASG scaling
###############################################################################
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.name_prefix}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale out when CPU > 70% for 4 minutes"
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${local.name_prefix}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 20
  alarm_description   = "Scale in when CPU < 20% for 4 minutes"
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }

  tags = var.common_tags
}
