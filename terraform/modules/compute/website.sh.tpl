#!/bin/bash
###############################################################################
# website.sh.tpl
# Runs ONCE on every EC2 instance launched by the ASG.
# Installs Nginx, writes the website, registers with ALB automatically.
###############################################################################
set -euo pipefail
exec > /var/log/userdata.log 2>&1
echo "Bootstrap started: ${env_name} at $(date -u)"

# ── Packages ──────────────────────────────────────────────────────────────────
dnf update -y
dnf install -y nginx amazon-cloudwatch-agent aws-cli jq python3

# ── Instance Metadata (IMDSv2) ────────────────────────────────────────────────
TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")
INSTANCE_ID=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
AZ=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || echo "unknown")
PRIVATE_IP=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo "unknown")

echo "Instance: $INSTANCE_ID | AZ: $AZ | IP: $PRIVATE_IP"

# ── App env file ──────────────────────────────────────────────────────────────
mkdir -p /etc/app
cat > /etc/app/env <<ENVFILE
ENVIRONMENT=${environment}
ENV_NAME=${env_name}
AWS_REGION=${aws_region}
INSTANCE_ID=$INSTANCE_ID
AZ=$AZ
PRIVATE_IP=$PRIVATE_IP
ENVFILE
chmod 600 /etc/app/env

# ── Website HTML ──────────────────────────────────────────────────────────────
mkdir -p /usr/share/nginx/html
cat > /usr/share/nginx/html/index.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1.0"/>
  <title>AI-Powered Infrastructure Monitoring</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{
      font-family:'Segoe UI',system-ui,sans-serif;
      background:linear-gradient(135deg,#0a0a1a 0%,#1a1040 45%,#0d1b2a 100%);
      min-height:100vh;color:#fff;
      display:flex;flex-direction:column;align-items:center;
      justify-content:center;padding:40px 20px;
    }
    /* top banner */
    .banner{
      width:100%;max-width:1000px;
      background:rgba(34,197,94,.12);
      border:1px solid rgba(34,197,94,.3);
      border-radius:10px;padding:12px 24px;
      margin-bottom:40px;font-size:13px;
      color:#86efac;text-align:center;
    }
    .banner strong{color:#fff}
    /* hero */
    .hero{text-align:center;max-width:760px;margin-bottom:48px}
    .badge{
      display:inline-block;
      background:rgba(99,102,241,.2);border:1px solid rgba(99,102,241,.4);
      color:#a5b4fc;padding:5px 20px;border-radius:50px;
      font-size:12px;letter-spacing:2px;text-transform:uppercase;margin-bottom:22px;
    }
    h1{
      font-size:clamp(2rem,5vw,3.2rem);font-weight:800;line-height:1.15;margin-bottom:18px;
      background:linear-gradient(135deg,#fff 0%,#a5b4fc 55%,#67e8f9 100%);
      -webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;
    }
    .sub{font-size:clamp(.95rem,2vw,1.1rem);color:#94a3b8;line-height:1.8;max-width:600px;margin:0 auto 14px}
    .note{font-size:.82rem;color:#475569}
    .note span{color:#22c55e;font-weight:600}
    /* cards */
    .cards{
      display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));
      gap:18px;max-width:1000px;width:100%;margin-bottom:36px;
    }
    .card{
      background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.08);
      border-radius:16px;padding:28px 20px;
      transition:transform .3s,border-color .3s,background .3s;
    }
    .card:hover{transform:translateY(-4px);border-color:rgba(99,102,241,.4);background:rgba(99,102,241,.08)}
    .icon{font-size:2.2rem;margin-bottom:12px}
    .ct{font-size:.95rem;font-weight:700;color:#e2e8f0;margin-bottom:7px}
    .cd{font-size:.8rem;color:#64748b;line-height:1.6}
    /* instance info */
    .info{
      display:flex;flex-wrap:wrap;justify-content:center;gap:22px;
      max-width:1000px;width:100%;
      background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.07);
      border-radius:14px;padding:22px 28px;margin-bottom:28px;
    }
    .ii{text-align:center;min-width:120px}
    .il{font-size:.68rem;text-transform:uppercase;letter-spacing:1.5px;color:#475569;margin-bottom:5px}
    .iv{font-size:.88rem;font-weight:600;color:#a5b4fc;word-break:break-all}
    .dot{display:inline-block;width:8px;height:8px;border-radius:50%;background:#22c55e;margin-right:4px;animation:blink 2s infinite}
    @keyframes blink{0%,100%{opacity:1}50%{opacity:.3}}
    /* scaling */
    .sc-wrap{max-width:1000px;width:100%;margin-bottom:28px}
    .sc-title{font-size:.7rem;text-transform:uppercase;letter-spacing:2px;color:#475569;text-align:center;margin-bottom:12px}
    .sc-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(195px,1fr));gap:10px}
    .sc-row{display:flex;align-items:center;gap:12px;background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.06);border-radius:10px;padding:13px 16px}
    .sp{font-size:1rem;font-weight:800;min-width:52px}
    .sp.g{color:#22c55e}.sp.y{color:#eab308}.sp.o{color:#f97316}.sp.r{color:#ef4444}
    .st{font-size:.78rem;color:#94a3b8;line-height:1.4}
    .st strong{color:#e2e8f0}
    footer{font-size:.72rem;color:#334155;text-align:center}
  </style>
</head>
<body>

  <div class="banner">
    <strong>✅ This webpage is configured on EC2 instances</strong>
    &nbsp;·&nbsp; Served by Nginx
    &nbsp;·&nbsp; Registered with Application Load Balancer
    &nbsp;·&nbsp; Managed by Auto Scaling Group
  </div>

  <div class="hero">
    <div class="badge">🤖 AI-Powered Platform</div>
    <h1>Welcome to AI-Powered<br/>Infrastructure Monitoring</h1>
    <p class="sub">
      Make Your Infrastructure Feel Fantastic with AI-Driven Insights,
      Smart Automation, and Real-Time Observability.
    </p>
    <p class="note">
      <span>●</span> Running on AWS EC2
      &nbsp;·&nbsp; Auto-registered with ALB
      &nbsp;·&nbsp; Discovered by Prometheus
    </p>
  </div>

  <div class="cards">
    <div class="card">
      <div class="icon">🧠</div>
      <div class="ct">AI-Driven Insights</div>
      <div class="cd">Intelligent anomaly detection and root cause analysis</div>
    </div>
    <div class="card">
      <div class="icon">📊</div>
      <div class="ct">Real-Time Metrics</div>
      <div class="cd">Live dashboards powered by Prometheus and Grafana</div>
    </div>
    <div class="card">
      <div class="icon">⚡</div>
      <div class="ct">Auto Scaling</div>
      <div class="cd">CPU and memory-driven elastic scaling — 1 to 8 instances</div>
    </div>
    <div class="card">
      <div class="icon">🌐</div>
      <div class="ct">Application Load Balancer</div>
      <div class="cd">ALB distributes traffic across all healthy instances</div>
    </div>
    <div class="card">
      <div class="icon">🔒</div>
      <div class="ct">Secure by Design</div>
      <div class="cd">IMDSv2 · Encrypted EBS · Private subnets · IAM roles</div>
    </div>
    <div class="card">
      <div class="icon">🏗️</div>
      <div class="ct">Terraform IaC</div>
      <div class="cd">100% infrastructure-as-code — reproducible and auditable</div>
    </div>
  </div>

  <div class="info">
    <div class="ii">
      <div class="il">Status</div>
      <div class="iv"><span class="dot"></span>Healthy</div>
    </div>
    <div class="ii">
      <div class="il">Environment</div>
      <div class="iv" id="e-env">…</div>
    </div>
    <div class="ii">
      <div class="il">Instance ID</div>
      <div class="iv" id="e-iid">…</div>
    </div>
    <div class="ii">
      <div class="il">Availability Zone</div>
      <div class="iv" id="e-az">…</div>
    </div>
    <div class="ii">
      <div class="il">Private IP</div>
      <div class="iv" id="e-ip">…</div>
    </div>
    <div class="ii">
      <div class="il">Region</div>
      <div class="iv" id="e-region">…</div>
    </div>
  </div>

  <div class="sc-wrap">
    <div class="sc-title">⚡ Auto Scaling Policy — CPU &amp; Memory Thresholds</div>
    <div class="sc-grid">
      <div class="sc-row"><div class="sp g">≤ 20%</div><div class="st"><strong>Scale In</strong> — remove 1 instance</div></div>
      <div class="sc-row"><div class="sp y">70–80%</div><div class="st"><strong>Scale Out</strong> — add +1 instance</div></div>
      <div class="sc-row"><div class="sp o">80–90%</div><div class="st"><strong>Scale Out</strong> — add +2 instances</div></div>
      <div class="sc-row"><div class="sp r">≥ 90%</div><div class="st"><strong>Scale Out</strong> — add +4 instances (max 8)</div></div>
    </div>
  </div>

  <footer>
    Observability Platform &nbsp;·&nbsp; AWS EC2 &nbsp;·&nbsp;
    Terraform &nbsp;·&nbsp; Prometheus &nbsp;·&nbsp; Grafana &nbsp;·&nbsp; ALB
  </footer>

  <script>
    fetch('/info').then(r=>r.json()).then(d=>{
      document.getElementById('e-env').textContent    = d.environment||'N/A';
      document.getElementById('e-iid').textContent    = d.instance_id||'N/A';
      document.getElementById('e-az').textContent     = d.az||'N/A';
      document.getElementById('e-ip').textContent     = d.private_ip||'N/A';
      document.getElementById('e-region').textContent = d.region||'N/A';
    }).catch(()=>{
      ['e-env','e-iid','e-az','e-ip','e-region']
        .forEach(id=>document.getElementById(id).textContent='N/A');
    });
  </script>
</body>
</html>
HTML

# ── Info endpoint (Python, port 8081) ─────────────────────────────────────────
cat > /usr/local/bin/infoserver.py <<PYEOF
#!/usr/bin/env python3
import http.server, json, os
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({
            "status":      "healthy",
            "environment": os.getenv("ENVIRONMENT","unknown"),
            "env_name":    os.getenv("ENV_NAME","unknown"),
            "instance_id": os.getenv("INSTANCE_ID","unknown"),
            "az":          os.getenv("AZ","unknown"),
            "private_ip":  os.getenv("PRIVATE_IP","unknown"),
            "region":      os.getenv("AWS_REGION","unknown")
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type","application/json")
        self.send_header("Access-Control-Allow-Origin","*")
        self.end_headers()
        self.wfile.write(body)
    def log_message(self,*a): pass
http.server.HTTPServer(("127.0.0.1",8081),H).serve_forever()
PYEOF
chmod +x /usr/local/bin/infoserver.py

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
[Install]
WantedBy=multi-user.target
SVC

# ── Nginx config ──────────────────────────────────────────────────────────────
cat > /etc/nginx/nginx.conf <<'NGINXEOF'
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
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
        location /info {
            proxy_pass http://127.0.0.1:8081;
            proxy_set_header Host $host;
            proxy_read_timeout 5s;
        }
        location / {
            try_files $uri $uri/ /index.html;
        }
    }
}
NGINXEOF

# ── CloudWatch Agent (memory + disk metrics) ──────────────────────────────────
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<CWEOF
{
  "agent":   { "metrics_collection_interval": 60, "run_as_user": "root" },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": {
      "AutoScalingGroupName": "\${aws:AutoScalingGroupName}",
      "InstanceId":           "\${aws:InstanceId}"
    },
    "metrics_collected": {
      "mem":  { "measurement": ["mem_used_percent"],  "metrics_collection_interval": 60 },
      "disk": { "measurement": ["disk_used_percent"], "resources": ["/"], "metrics_collection_interval": 60 }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          { "file_path": "/var/log/nginx/access.log", "log_group_name": "/aws/ec2/${env_name}/nginx/access", "log_stream_name": "{instance_id}" },
          { "file_path": "/var/log/nginx/error.log",  "log_group_name": "/aws/ec2/${env_name}/nginx/error",  "log_stream_name": "{instance_id}" }
        ]
      }
    }
  }
}
CWEOF

# ── Start services ────────────────────────────────────────────────────────────
systemctl daemon-reload
systemctl enable nginx infoserver amazon-cloudwatch-agent
systemctl start  nginx infoserver amazon-cloudwatch-agent

sleep 2
curl -sf http://localhost/health | grep -q healthy \
  && echo "✅ Nginx OK" \
  || echo "❌ Nginx FAILED — check /var/log/nginx/error.log"

echo "Bootstrap complete: ${env_name} | $INSTANCE_ID | $AZ"
