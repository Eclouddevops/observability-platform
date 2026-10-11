#!/bin/bash
###############################################################################
# website.sh.tpl — EC2 bootstrap script
# Runs once on every new instance launched by the ASG
#
# What this does:
#   1. Installs Nginx + CloudWatch Agent
#   2. Writes the static website HTML
#   3. Configures Nginx to serve on port ${app_port}
#   4. Starts Nginx → ALB /health check passes → traffic flows
#   5. Starts CloudWatch Agent → sends memory metrics → scaling works
###############################################################################
set -euo pipefail
exec > /var/log/userdata.log 2>&1

echo "======================================================"
echo " Bootstrap starting: ${env_name} / ${environment}"
echo " Time: $(date -u)"
echo "======================================================"

###############################################################################
# Step 1 — System update + install packages
###############################################################################
dnf update -y
dnf install -y nginx amazon-cloudwatch-agent aws-cli jq python3

###############################################################################
# Step 2 — Get instance metadata (IMDSv2)
###############################################################################
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")

if [[ -n "$TOKEN" ]]; then
  INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
  AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || echo "unknown")
  PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo "unknown")
else
  INSTANCE_ID="unknown"
  AZ="unknown"
  PRIVATE_IP="unknown"
fi

echo "Instance ID : $INSTANCE_ID"
echo "AZ          : $AZ"
echo "Private IP  : $PRIVATE_IP"

###############################################################################
# Step 3 — Fetch DB credentials from Secrets Manager
###############################################################################
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "${db_secret_name}" \
  --region "${aws_region}" \
  --query SecretString \
  --output text 2>/dev/null || echo "{}")

mkdir -p /etc/app
cat > /etc/app/env <<ENVFILE
ENVIRONMENT=${environment}
ENV_NAME=${env_name}
AWS_REGION=${aws_region}
INSTANCE_ID=$INSTANCE_ID
AZ=$AZ
DB_HOST=$(echo "$SECRET" | jq -r '.host // ""' 2>/dev/null || echo "")
DB_USER=$(echo "$SECRET" | jq -r '.username // ""' 2>/dev/null || echo "")
DB_NAME=$(echo "$SECRET" | jq -r '.dbname // ""' 2>/dev/null || echo "")
ENVFILE
chmod 600 /etc/app/env

###############################################################################
# Step 4 — Write the static HTML website
###############################################################################
mkdir -p /usr/share/nginx/html

cat > /usr/share/nginx/html/index.html <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>AI-Powered Infrastructure Monitoring</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
      background: linear-gradient(135deg, #0a0a1a 0%, #1a1040 40%, #0d1b2a 100%);
      min-height: 100vh;
      color: #fff;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 40px 20px;
    }

    /* ── Top banner ── */
    .top-banner {
      width: 100%;
      max-width: 1100px;
      background: rgba(99,102,241,0.15);
      border: 1px solid rgba(99,102,241,0.3);
      border-radius: 8px;
      padding: 10px 20px;
      margin-bottom: 40px;
      font-size: 13px;
      color: #a5b4fc;
      text-align: center;
      letter-spacing: 0.5px;
    }
    .top-banner strong { color: #fff; }

    /* ── Hero ── */
    .hero { text-align: center; max-width: 780px; margin-bottom: 50px; }

    .badge {
      display: inline-block;
      background: rgba(99,102,241,0.2);
      border: 1px solid rgba(99,102,241,0.4);
      color: #a5b4fc;
      padding: 5px 18px;
      border-radius: 50px;
      font-size: 12px;
      letter-spacing: 2px;
      text-transform: uppercase;
      margin-bottom: 24px;
    }

    h1 {
      font-size: clamp(2rem, 5vw, 3.4rem);
      font-weight: 800;
      line-height: 1.15;
      margin-bottom: 20px;
      background: linear-gradient(135deg, #ffffff 0%, #a5b4fc 60%, #67e8f9 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      background-clip: text;
    }

    .subtitle {
      font-size: clamp(0.95rem, 2vw, 1.15rem);
      color: #94a3b8;
      line-height: 1.8;
      max-width: 620px;
      margin: 0 auto 10px;
    }

    .configured-note {
      margin-top: 16px;
      font-size: 0.85rem;
      color: #64748b;
    }
    .configured-note span {
      color: #22c55e;
      font-weight: 600;
    }

    /* ── Feature cards ── */
    .cards {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 20px;
      max-width: 1100px;
      width: 100%;
      margin-bottom: 40px;
    }

    .card {
      background: rgba(255,255,255,0.05);
      border: 1px solid rgba(255,255,255,0.08);
      border-radius: 18px;
      padding: 30px 22px;
      transition: transform .3s, border-color .3s, background .3s;
      cursor: default;
    }
    .card:hover {
      transform: translateY(-5px);
      border-color: rgba(99,102,241,0.4);
      background: rgba(99,102,241,0.08);
    }
    .card-icon  { font-size: 2.4rem; margin-bottom: 14px; }
    .card-title { font-size: 1rem; font-weight: 700; color: #e2e8f0; margin-bottom: 8px; }
    .card-desc  { font-size: 0.82rem; color: #64748b; line-height: 1.6; }

    /* ── Instance info bar ── */
    .info-bar {
      display: flex;
      flex-wrap: wrap;
      justify-content: center;
      gap: 24px;
      max-width: 1100px;
      width: 100%;
      background: rgba(255,255,255,0.03);
      border: 1px solid rgba(255,255,255,0.07);
      border-radius: 16px;
      padding: 24px 30px;
      margin-bottom: 30px;
    }

    .info-item { text-align: center; min-width: 130px; }
    .info-label {
      font-size: 0.7rem;
      text-transform: uppercase;
      letter-spacing: 1.5px;
      color: #475569;
      margin-bottom: 6px;
    }
    .info-value {
      font-size: 0.88rem;
      font-weight: 600;
      color: #a5b4fc;
      word-break: break-all;
    }

    .dot {
      display: inline-block;
      width: 8px; height: 8px;
      border-radius: 50%;
      background: #22c55e;
      margin-right: 5px;
      animation: blink 2s infinite;
    }
    @keyframes blink {
      0%,100% { opacity: 1; }
      50%      { opacity: 0.3; }
    }

    /* ── Scaling chart ── */
    .scaling-section {
      max-width: 1100px;
      width: 100%;
      margin-bottom: 30px;
    }
    .scaling-title {
      font-size: 0.75rem;
      text-transform: uppercase;
      letter-spacing: 2px;
      color: #475569;
      text-align: center;
      margin-bottom: 14px;
    }
    .scaling-rows {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 12px;
    }
    .scale-row {
      display: flex;
      align-items: center;
      gap: 12px;
      background: rgba(255,255,255,0.03);
      border: 1px solid rgba(255,255,255,0.06);
      border-radius: 10px;
      padding: 14px 18px;
    }
    .scale-pct {
      font-size: 1.1rem;
      font-weight: 800;
      min-width: 48px;
    }
    .scale-pct.green  { color: #22c55e; }
    .scale-pct.yellow { color: #eab308; }
    .scale-pct.orange { color: #f97316; }
    .scale-pct.red    { color: #ef4444; }
    .scale-text { font-size: 0.8rem; color: #94a3b8; line-height: 1.4; }
    .scale-text strong { color: #e2e8f0; }

    /* ── Footer ── */
    footer {
      font-size: 0.75rem;
      color: #334155;
      text-align: center;
    }
  </style>
</head>
<body>

  <div class="top-banner">
    <strong>✅ This webpage is configured on EC2 instances</strong>
    &nbsp;|&nbsp; Served by Nginx &nbsp;|&nbsp; Auto-registered with Application Load Balancer
    &nbsp;|&nbsp; Auto Scaling Group manages this fleet
  </div>

  <section class="hero">
    <div class="badge">🤖 AI-Powered Platform</div>

    <h1>Welcome to AI-Powered<br/>Infrastructure Monitoring</h1>

    <p class="subtitle">
      Make Your Infrastructure Feel Fantastic with AI-Driven Insights,
      Smart Automation, and Real-Time Observability.
    </p>

    <p class="configured-note">
      <span>●</span> Running on AWS EC2 &nbsp;·&nbsp;
      Served via ALB &nbsp;·&nbsp;
      Auto-discovered by Prometheus
    </p>
  </section>

  <div class="cards">
    <div class="card">
      <div class="card-icon">🧠</div>
      <div class="card-title">AI-Driven Insights</div>
      <div class="card-desc">Intelligent anomaly detection and root cause analysis powered by machine learning</div>
    </div>
    <div class="card">
      <div class="card-icon">📊</div>
      <div class="card-title">Real-Time Metrics</div>
      <div class="card-desc">Live dashboards powered by Prometheus and Grafana — updated every 30 seconds</div>
    </div>
    <div class="card">
      <div class="card-icon">⚡</div>
      <div class="card-title">Auto Scaling</div>
      <div class="card-desc">CPU and memory-driven elastic scaling — from 1 to 8 instances automatically</div>
    </div>
    <div class="card">
      <div class="card-icon">🔒</div>
      <div class="card-title">Secure by Design</div>
      <div class="card-desc">Zero hardcoded secrets · IMDSv2 · Encrypted EBS · Private subnets · IAM roles</div>
    </div>
    <div class="card">
      <div class="card-icon">🌐</div>
      <div class="card-title">Application Load Balancer</div>
      <div class="card-desc">ALB distributes traffic across all healthy EC2 instances automatically</div>
    </div>
    <div class="card">
      <div class="card-icon">🏗️</div>
      <div class="card-title">Terraform IaC</div>
      <div class="card-desc">100% infrastructure-as-code — reproducible, version-controlled, auditable</div>
    </div>
  </div>

  <!-- Instance info — filled by JavaScript from /info endpoint -->
  <div class="info-bar" id="info-bar">
    <div class="info-item">
      <div class="info-label">Status</div>
      <div class="info-value"><span class="dot"></span>Healthy</div>
    </div>
    <div class="info-item">
      <div class="info-label">Environment</div>
      <div class="info-value" id="env-val">…</div>
    </div>
    <div class="info-item">
      <div class="info-label">Instance ID</div>
      <div class="info-value" id="iid-val">…</div>
    </div>
    <div class="info-item">
      <div class="info-label">Availability Zone</div>
      <div class="info-value" id="az-val">…</div>
    </div>
    <div class="info-item">
      <div class="info-label">Private IP</div>
      <div class="info-value" id="ip-val">…</div>
    </div>
    <div class="info-item">
      <div class="info-label">Region</div>
      <div class="info-value" id="region-val">…</div>
    </div>
  </div>

  <!-- Scaling policy reference -->
  <div class="scaling-section">
    <div class="scaling-title">⚡ Auto Scaling Policy — CPU &amp; Memory</div>
    <div class="scaling-rows">
      <div class="scale-row">
        <div class="scale-pct green">≤ 20%</div>
        <div class="scale-text"><strong>Scale In</strong> — remove 1 instance</div>
      </div>
      <div class="scale-row">
        <div class="scale-pct yellow">70–80%</div>
        <div class="scale-text"><strong>Scale Out</strong> — add 1 instance</div>
      </div>
      <div class="scale-row">
        <div class="scale-pct orange">80–90%</div>
        <div class="scale-text"><strong>Scale Out</strong> — add 2 instances</div>
      </div>
      <div class="scale-row">
        <div class="scale-pct red">≥ 90%</div>
        <div class="scale-text"><strong>Scale Out</strong> — add 4 instances (max 8)</div>
      </div>
    </div>
  </div>

  <footer>
    Observability Platform &nbsp;·&nbsp;
    AWS EC2 &nbsp;·&nbsp; Terraform &nbsp;·&nbsp;
    Prometheus &nbsp;·&nbsp; Grafana &nbsp;·&nbsp;
    Application Load Balancer
  </footer>

  <script>
    // Fetch instance info from the /info endpoint (served by Python on 127.0.0.1:8081)
    fetch('/info')
      .then(r => r.json())
      .then(d => {
        document.getElementById('env-val').textContent    = d.environment || 'N/A';
        document.getElementById('iid-val').textContent    = d.instance_id  || 'N/A';
        document.getElementById('az-val').textContent     = d.az           || 'N/A';
        document.getElementById('ip-val').textContent     = d.private_ip   || 'N/A';
        document.getElementById('region-val').textContent = d.region        || 'N/A';
      })
      .catch(() => {
        ['env-val','iid-val','az-val','ip-val','region-val']
          .forEach(id => document.getElementById(id).textContent = 'N/A');
      });
  </script>
</body>
</html>
HTMLEOF

###############################################################################
# Step 5 — Write /info endpoint (tiny Python server on 127.0.0.1:8081)
###############################################################################
cat > /usr/local/bin/infoserver.py <<PYEOF
#!/usr/bin/env python3
import http.server, json, os

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        data = json.dumps({
            "status":       "healthy",
            "environment":  os.getenv("ENVIRONMENT",  "unknown"),
            "env_name":     os.getenv("ENV_NAME",     "unknown"),
            "instance_id":  os.getenv("INSTANCE_ID",  "unknown"),
            "az":           os.getenv("AZ",           "unknown"),
            "private_ip":   os.getenv("PRIVATE_IP",   "unknown"),
            "region":       os.getenv("AWS_REGION",   "unknown")
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

# systemd unit for info server
cat > /etc/systemd/system/infoserver.service <<SVC
[Unit]
Description=Instance Info API
After=network.target

[Service]
Type=simple
EnvironmentFile=/etc/app/env
ExecStart=/usr/bin/python3 /usr/local/bin/infoserver.py
Restart=always
RestartSec=3
StandardOutput=journal

[Install]
WantedBy=multi-user.target
SVC

###############################################################################
# Step 6 — Nginx config
#   GET /          → serve index.html (static website)
#   GET /health    → return 200 "healthy" (ALB health check)
#   GET /info      → proxy to Python on 127.0.0.1:8081
###############################################################################
cat > /etc/nginx/nginx.conf <<'NGINXEOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /run/nginx.pid;

events { worker_connections 1024; }

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;
    server_tokens off;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent"';
    access_log /var/log/nginx/access.log main;

    server {
        listen 80 default_server;
        server_name _;
        root /usr/share/nginx/html;
        index index.html;

        # ALB health check — must return 200
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }

        # Instance info API
        location /info {
            proxy_pass         http://127.0.0.1:8081;
            proxy_set_header   Host $host;
            proxy_read_timeout 5s;
        }

        # Static website
        location / {
            try_files $uri $uri/ /index.html;
        }
    }
}
NGINXEOF

###############################################################################
# Step 7 — CloudWatch Agent config (memory + disk metrics + Nginx logs)
###############################################################################
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<CWEOF
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": {
      "AutoScalingGroupName": "\$${aws:AutoScalingGroupName}",
      "InstanceId":           "\$${aws:InstanceId}"
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
            "log_group_name": "/aws/ec2/${env_name}/nginx/access",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "/aws/ec2/${env_name}/nginx/error",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
CWEOF

###############################################################################
# Step 8 — Start everything
###############################################################################
systemctl daemon-reload
systemctl enable nginx infoserver amazon-cloudwatch-agent
systemctl start  nginx infoserver amazon-cloudwatch-agent

# Verify Nginx is up
sleep 2
if curl -sf http://localhost/health | grep -q healthy; then
  echo "✅ Nginx health check: PASSED"
else
  echo "❌ Nginx health check: FAILED — check /var/log/nginx/error.log"
fi

echo "======================================================"
echo " Bootstrap complete: ${env_name}"
echo " Instance: $INSTANCE_ID | AZ: $AZ"
echo " Website:  http://<ALB-DNS>/"
echo " Health:   http://<ALB-DNS>/health"
echo " Info:     http://<ALB-DNS>/info"
echo "======================================================"
