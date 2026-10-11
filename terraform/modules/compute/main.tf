###############################################################################
# Module: compute — IAM role + Launch Template + ASG (4 × t2.micro EC2)
###############################################################################

# ── IAM Role for EC2 ──────────────────────────────────────────────────────────
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
resource "aws_launch_template" "this" {
  name          = "${var.env_name}-lt"
  image_id      = var.ami_id != "" ? var.ami_id : data.aws_ami.al2023.id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.ec2_sg_id]
    delete_on_termination       = true
  }

  # IMDSv2 enforced
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring { enabled = true }

  # 30GB — required by Amazon Linux 2023 AMI snapshot
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    set -euo pipefail
    dnf update -y
    dnf install -y amazon-cloudwatch-agent aws-cli jq

    # Fetch DB credentials from Secrets Manager
    SECRET=$(aws secretsmanager get-secret-value \
      --secret-id "${var.db_secret_name}" \
      --region "${var.aws_region}" \
      --query SecretString --output text 2>/dev/null || echo "{}")

    mkdir -p /etc/app
    cat > /etc/app/env <<ENV
    ENVIRONMENT=${var.environment}
    DB_HOST=$(echo $SECRET | jq -r '.host // empty')
    DB_USER=$(echo $SECRET | jq -r '.username // empty')
    DB_NAME=$(echo $SECRET | jq -r '.dbname // empty')
    AWS_REGION=${var.aws_region}
    ENV
    chmod 600 /etc/app/env

    # Simple HTTP health endpoint so ALB health checks pass
    dnf install -y python3
    cat > /usr/local/bin/healthserver.py <<'PYEOF'
    import http.server, socketserver
    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'OK')
        def log_message(self, *a): pass
    socketserver.TCPServer(('', ${var.app_port}), H).serve_forever()
    PYEOF

    nohup python3 /usr/local/bin/healthserver.py &>/var/log/healthserver.log &
    echo "Bootstrap complete: ${var.env_name}"
  USERDATA
  )

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags, {
      Name        = "${var.env_name}-ec2"
      Environment = var.environment
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

  target_group_arns = [
    var.alb_target_group_arn,
    var.nlb_target_group_arn,
  ]

  # EC2 health check — does NOT require app to be running
  # Switch to ELB health check once your application is deployed
  health_check_type         = "EC2"
  health_check_grace_period = 300

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceCapacity",
    "GroupPendingCapacity",
    "GroupTerminatingCapacity",
    "GroupTotalCapacity",
  ]

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 120
    }
  }

  dynamic "tag" {
    for_each = merge(var.common_tags, {
      Name        = "${var.env_name}-ec2"
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
    ignore_changes        = [desired_capacity]
  }
}

# ── CPU-based scaling policies ────────────────────────────────────────────────
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.env_name}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.this.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.env_name}-scale-in"
  autoscaling_group_name = aws_autoscaling_group.this.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.env_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.this.name }
  tags                = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.env_name}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 20
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.this.name }
  tags                = var.common_tags
}
