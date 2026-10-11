###############################################################################
# Module: compute
#
# Provisions:
#   - IAM Role + Instance Profile
#   - Launch Template with Nginx static website
#   - Auto Scaling Group (desired=1, min=1, max=8)
#   - Step Scaling policies:
#       CPU/Memory >= 70% → add 1 instance
#       CPU/Memory >= 80% → add 2 instances
#       CPU/Memory >= 90% → scale to max (8 instances)
#       CPU/Memory <= 20% → remove 1 instance
#   - CloudWatch Alarms for CPU scaling
#   - CloudWatch Agent for Memory metrics
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

  # 30GB root volume
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

    ###########################################################################
    # System update + install packages
    ###########################################################################
    dnf update -y
    dnf install -y nginx amazon-cloudwatch-agent aws-cli jq python3

    ###########################################################################
    # Fetch environment info
    ###########################################################################
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id \
      --header "X-aws-ec2-metadata-token: $(curl -s -XPUT \
      'http://169.254.169.254/latest/api/token' \
      -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')" 2>/dev/null || echo "unknown")

    AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone \
      --header "X-aws-ec2-metadata-token: $(curl -s -XPUT \
      'http://169.254.169.254/latest/api/token' \
      -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')" 2>/dev/null || echo "unknown")

    ENV_NAME="${var.env_name}"
    ENVIRONMENT="${var.environment}"
    AWS_REGION="${var.aws_region}"

    ###########################################################################
    # Fetch DB credentials from Secrets Manager
    ###########################################################################
    SECRET=$(aws secretsmanager get-secret-value \
      --secret-id "${var.db_secret_name}" \
      --region "${var.aws_region}" \
      --query SecretString \
      --output text 2>/dev/null || echo "{}")

    mkdir -p /etc/app
    cat > /etc/app/env <<ENV
    ENVIRONMENT=${var.environment}
    ENV_NAME=${var.env_name}
    DB_HOST=$(echo $SECRET | jq -r '.host // ""')
    DB_USER=$(echo $SECRET | jq -r '.username // ""')
    DB_NAME=$(echo $SECRET | jq -r '.dbname // ""')
    AWS_REGION=${var.aws_region}
    ENV
    chmod 600 /etc/app/env

    ###########################################################################
    # Nginx — Static Website
    ###########################################################################
    cat > /usr/share/nginx/html/index.html <<'HTML'
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>AI-Powered Infrastructure Monitoring</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
          font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
          background: linear-gradient(135deg, #0f0c29 0%, #302b63 50%, #24243e 100%);
          min-height: 100vh;
          display: flex;
          align-items: center;
          justify-content: center;
          color: #fff;
        }
        .container {
          text-align: center;
          padding: 60px 40px;
          max-width: 900px;
        }
        .badge {
          display: inline-block;
          background: rgba(99,102,241,0.25);
          border: 1px solid rgba(99,102,241,0.5);
          color: #a5b4fc;
          padding: 6px 20px;
          border-radius: 50px;
          font-size: 13px;
          letter-spacing: 1.5px;
          text-transform: uppercase;
          margin-bottom: 30px;
        }
        h1 {
          font-size: clamp(2rem, 5vw, 3.5rem);
          font-weight: 800;
          line-height: 1.2;
          margin-bottom: 20px;
          background: linear-gradient(135deg, #fff 0%, #a5b4fc 100%);
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
          background-clip: text;
        }
        .subtitle {
          font-size: clamp(1rem, 2vw, 1.25rem);
          color: #94a3b8;
          line-height: 1.7;
          max-width: 640px;
          margin: 0 auto 50px;
        }
        .cards {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
          gap: 20px;
          margin-bottom: 50px;
        }
        .card {
          background: rgba(255,255,255,0.06);
          border: 1px solid rgba(255,255,255,0.1);
          border-radius: 16px;
          padding: 28px 20px;
          transition: transform 0.3s, background 0.3s;
        }
        .card:hover {
          transform: translateY(-4px);
          background: rgba(255,255,255,0.1);
        }
        .card-icon { font-size: 2.2rem; margin-bottom: 12px; }
        .card-title {
          font-size: 0.95rem;
          font-weight: 600;
          color: #e2e8f0;
          margin-bottom: 6px;
        }
        .card-desc { font-size: 0.82rem; color: #64748b; }
        .status-bar {
          display: flex;
          justify-content: center;
          gap: 30px;
          flex-wrap: wrap;
          padding: 20px 30px;
          background: rgba(255,255,255,0.04);
          border: 1px solid rgba(255,255,255,0.08);
          border-radius: 14px;
          margin-bottom: 30px;
        }
        .status-item { text-align: center; }
        .status-label {
          font-size: 0.75rem;
          color: #64748b;
          text-transform: uppercase;
          letter-spacing: 1px;
          margin-bottom: 4px;
        }
        .status-value {
          font-size: 0.9rem;
          font-weight: 600;
          color: #a5b4fc;
          word-break: break-all;
        }
        .status-dot {
          display: inline-block;
          width: 8px; height: 8px;
          border-radius: 50%;
          background: #22c55e;
          margin-right: 6px;
          animation: pulse 2s infinite;
        }
        @keyframes pulse {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.4; }
        }
        .footer {
          font-size: 0.8rem;
          color: #475569;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="badge">🤖 AI-Powered Platform</div>

        <h1>Welcome to AI-Powered<br/>Infrastructure Monitoring</h1>

        <p class="subtitle">
          Make Your Infrastructure Feel Fantastic with AI-Driven Insights,
          Smart Automation, and Real-Time Observability.
        </p>

        <div class="cards">
          <div class="card">
            <div class="card-icon">🧠</div>
            <div class="card-title">AI Insights</div>
            <div class="card-desc">Intelligent anomaly detection and root cause analysis</div>
          </div>
          <div class="card">
            <div class="card-icon">📊</div>
            <div class="card-title">Real-Time Metrics</div>
            <div class="card-desc">Live dashboards powered by Prometheus and Grafana</div>
          </div>
          <div class="card">
            <div class="card-icon">⚡</div>
            <div class="card-title">Auto Scaling</div>
            <div class="card-desc">CPU and memory-driven elastic scaling up to 8 nodes</div>
          </div>
          <div class="card">
            <div class="card-icon">🔒</div>
            <div class="card-title">Secure by Design</div>
            <div class="card-desc">Zero hardcoded secrets, IAM roles, encrypted storage</div>
          </div>
        </div>

        <div class="status-bar" id="status">
          <div class="status-item">
            <div class="status-label">Status</div>
            <div class="status-value"><span class="status-dot"></span>Healthy</div>
          </div>
          <div class="status-item">
            <div class="status-label">Environment</div>
            <div class="status-value" id="env-val">Loading...</div>
          </div>
          <div class="status-item">
            <div class="status-label">Instance ID</div>
            <div class="status-value" id="iid-val">Loading...</div>
          </div>
          <div class="status-item">
            <div class="status-label">Region</div>
            <div class="status-value" id="az-val">Loading...</div>
          </div>
        </div>

        <div class="footer">
          Observability Platform &mdash; Powered by AWS &bull; Terraform &bull; Prometheus &bull; Grafana
        </div>
      </div>

      <script>
        fetch('/info').then(r=>r.json()).then(d=>{
          document.getElementById('env-val').textContent = d.environment || 'N/A';
          document.getElementById('iid-val').textContent = d.instance_id || 'N/A';
          document.getElementById('az-val').textContent  = d.az || 'N/A';
        }).catch(()=>{
          document.getElementById('env-val').textContent = 'N/A';
          document.getElementById('iid-val').textContent = 'N/A';
          document.getElementById('az-val').textContent  = 'N/A';
        });
      </script>
    </body>
    </html>
    HTML

    ###########################################################################
    # Info endpoint — served by Python on port 8081, proxied by Nginx
    ###########################################################################
    cat > /usr/local/bin/infoserver.py <<PYEOF
    #!/usr/bin/env python3
    import http.server, json, os

    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            data = json.dumps({
                "environment": os.getenv("ENVIRONMENT", "unknown"),
                "env_name":    os.getenv("ENV_NAME",    "unknown"),
                "instance_id": "$INSTANCE_ID",
                "az":          "$AZ",
                "region":      "$AWS_REGION",
                "status":      "healthy"
            })
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(data.encode())
        def log_message(self, *a): pass

    http.server.HTTPServer(("127.0.0.1", 8081), H).serve_forever()
    PYEOF
    chmod +x /usr/local/bin/infoserver.py

    # Start info server as systemd service
    cat > /etc/systemd/system/infoserver.service <<SVC
    [Unit]
    Description=Info API Server
    After=network.target

    [Service]
    Type=simple
    EnvironmentFile=/etc/app/env
    ExecStart=/usr/bin/python3 /usr/local/bin/infoserver.py
    Restart=always
    RestartSec=5
    StandardOutput=journal
    StandardError=journal

    [Install]
    WantedBy=multi-user.target
    SVC

    ###########################################################################
    # Nginx config — serve static site + proxy /info to Python
    ###########################################################################
    cat > /etc/nginx/nginx.conf <<'NGINXCONF'
    user nginx;
    worker_processes auto;
    error_log /var/log/nginx/error.log warn;
    pid /run/nginx.pid;

    events { worker_connections 1024; }

    http {
        include       /etc/nginx/mime.types;
        default_type  application/octet-stream;
        sendfile on;
        keepalive_timeout 65;
        server_tokens off;

        server {
            listen 80 default_server;
            server_name _;
            root /usr/share/nginx/html;
            index index.html;

            # Health check endpoint for ALB
            location /health {
                access_log off;
                return 200 "healthy\n";
                add_header Content-Type text/plain;
            }

            # Instance info API (proxied to Python)
            location /info {
                proxy_pass http://127.0.0.1:8081;
                proxy_set_header Host $host;
            }

            # Static site
            location / {
                try_files $uri $uri/ /index.html;
            }
        }
    }
    NGINXCONF

    ###########################################################################
    # CloudWatch Agent config — sends Memory + Disk metrics to CloudWatch
    # These are used by the Memory scaling alarms
    ###########################################################################
    mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<CWCONFIG
    {
      "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "root"
      },
      "metrics": {
        "namespace": "CWAgent",
        "append_dimensions": {
          "AutoScalingGroupName": "$${aws:AutoScalingGroupName}",
          "InstanceId": "$${aws:InstanceId}"
        },
        "metrics_collected": {
          "mem": {
            "measurement": ["mem_used_percent"],
            "metrics_collection_interval": 60
          },
          "disk": {
            "measurement": ["disk_used_percent"],
            "resources": ["/"],
            "metrics_collection_interval": 60
          }
        }
      },
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/log/nginx/access.log",
                "log_group_name": "/aws/ec2/${var.env_name}/nginx/access",
                "log_stream_name": "{instance_id}"
              },
              {
                "file_path": "/var/log/nginx/error.log",
                "log_group_name": "/aws/ec2/${var.env_name}/nginx/error",
                "log_stream_name": "{instance_id}"
              }
            ]
          }
        }
      }
    }
    CWCONFIG

    ###########################################################################
    # Start all services
    ###########################################################################
    systemctl daemon-reload
    systemctl enable nginx infoserver amazon-cloudwatch-agent
    systemctl start nginx infoserver amazon-cloudwatch-agent

    echo "Bootstrap complete: ${var.env_name} on $INSTANCE_ID ($AZ)"
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

###############################################################################
# Step Scaling Policies
#   CPU/Memory >= 70% → +1 instance
#   CPU/Memory >= 80% → +2 instances
#   CPU/Memory >= 90% → +4 instances (rushes toward max=8)
#   CPU/Memory <= 20% → -1 instance
###############################################################################

# ── Scale OUT — Step Policy ───────────────────────────────────────────────────
resource "aws_autoscaling_policy" "scale_out_step" {
  name                      = "${var.env_name}-scale-out-step"
  autoscaling_group_name    = aws_autoscaling_group.this.name
  policy_type               = "StepScaling"
  adjustment_type           = "ChangeInCapacity"
  estimated_instance_warmup = 120

  step_adjustment {
    metric_interval_lower_bound = 0   # 70-80% → +1
    metric_interval_upper_bound = 10
    scaling_adjustment          = 1
  }

  step_adjustment {
    metric_interval_lower_bound = 10  # 80-90% → +2
    metric_interval_upper_bound = 20
    scaling_adjustment          = 2
  }

  step_adjustment {
    metric_interval_lower_bound = 20  # 90%+ → +4
    scaling_adjustment          = 4
  }
}

# ── Scale IN — Simple Policy ──────────────────────────────────────────────────
resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.env_name}-scale-in"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

###############################################################################
# CPU Scaling Alarms
###############################################################################

# CPU >= 70% → trigger step scale-out
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.env_name}-cpu-high-70"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "CPU >= 70% — step scale out (+1/+2/+4)"
  alarm_actions       = [aws_autoscaling_policy.scale_out_step.arn]
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.this.name }
  treat_missing_data  = "notBreaching"
  tags                = var.common_tags
}

# CPU <= 20% → scale in
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.env_name}-cpu-low-20"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 20
  alarm_description   = "CPU <= 20% — scale in (-1)"
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.this.name }
  treat_missing_data  = "notBreaching"
  tags                = var.common_tags
}

###############################################################################
# Memory Scaling Alarms (via CloudWatch Agent — CWAgent namespace)
###############################################################################

# Memory >= 70% → step scale-out
resource "aws_cloudwatch_metric_alarm" "mem_high" {
  alarm_name          = "${var.env_name}-mem-high-70"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Memory >= 70% — step scale out (+1/+2/+4)"
  alarm_actions       = [aws_autoscaling_policy.scale_out_step.arn]
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.this.name }
  treat_missing_data  = "notBreaching"
  tags                = var.common_tags
}

# Memory <= 20% → scale in
resource "aws_cloudwatch_metric_alarm" "mem_low" {
  alarm_name          = "${var.env_name}-mem-low-20"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period              = 120
  statistic           = "Average"
  threshold           = 20
  alarm_description   = "Memory <= 20% — scale in (-1)"
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.this.name }
  treat_missing_data  = "notBreaching"
  tags                = var.common_tags
}
