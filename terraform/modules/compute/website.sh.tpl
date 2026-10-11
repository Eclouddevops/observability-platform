#!/bin/bash
###############################################################################
# website.sh.tpl
# Runs on every EC2 instance launched by the ASG
# - Installs Apache (httpd)
# - Writes UAT or DEV specific website
# - /health endpoint for ALB health check
# - /info   endpoint for instance metadata
# - /load   endpoint to check load test status
# - Installs stress tool for CPU/Memory load testing
###############################################################################
set -euo pipefail
exec > /var/log/userdata.log 2>&1
echo "Bootstrap started: ${env_name} at $(date -u)"

###############################################################################
# 1 — Packages
###############################################################################
dnf update -y
dnf install -y httpd amazon-cloudwatch-agent aws-cli jq python3 stress-ng

###############################################################################
# 2 — Instance Metadata (IMDSv2)
###############################################################################
TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")

INSTANCE_ID=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
AZ=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || echo "unknown")
PRIVATE_IP=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo "unknown")
INSTANCE_TYPE=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo "unknown")

echo "Instance: $INSTANCE_ID | AZ: $AZ | IP: $PRIVATE_IP | Type: $INSTANCE_TYPE"

###############################################################################
# 3 — Environment-specific variables
###############################################################################
ENV_UPPER=$(echo "${environment}" | tr '[:lower:]' '[:upper:]')

# Colour theme per environment
if [[ "${environment}" == "uat" ]]; then
  ENV_COLOR="#7c3aed"        # purple for UAT
  ENV_BADGE_COLOR="#ede9fe"
  ENV_ACCENT="#a78bfa"
  ENV_BORDER="rgba(124,58,237,0.4)"
  ENV_BG="linear-gradient(135deg,#1e0a3c 0%,#2d1b69 45%,#0d0b26 100%)"
else
  ENV_COLOR="#0369a1"        # blue for DEV
  ENV_BADGE_COLOR="#e0f2fe"
  ENV_ACCENT="#38bdf8"
  ENV_BORDER="rgba(3,105,161,0.4)"
  ENV_BG="linear-gradient(135deg,#0a1628 0%,#0c2340 45%,#060d1a 100%)"
fi

###############################################################################
# 4 — Write Apache config
###############################################################################
cat > /etc/httpd/conf.d/website.conf <<'APACHECONF'
ServerName localhost

<VirtualHost *:80>
    DocumentRoot /var/www/html
    DirectoryIndex index.html

    # ALB health check
    <Location /health>
        SetHandler default-handler
    </Location>

    # Pass /info to Python backend
    ProxyPass        /info http://127.0.0.1:8081/info
    ProxyPassReverse /info http://127.0.0.1:8081/info

    # Pass /load-status to Python backend
    ProxyPass        /load-status http://127.0.0.1:8081/load-status
    ProxyPassReverse /load-status http://127.0.0.1:8081/load-status

    <Directory /var/www/html>
        Options -Indexes
        AllowOverride None
        Require all granted
    </Directory>

    ErrorLog  /var/log/httpd/error.log
    CustomLog /var/log/httpd/access.log combined
</VirtualHost>
APACHECONF

# Enable proxy modules
sed -i 's/#LoadModule proxy_module/LoadModule proxy_module/' \
  /etc/httpd/conf.modules.d/*.conf 2>/dev/null || true
echo "LoadModule proxy_module modules/mod_proxy.so"    >> /etc/httpd/conf/httpd.conf 2>/dev/null || true
echo "LoadModule proxy_http_module modules/mod_proxy_http.so" >> /etc/httpd/conf/httpd.conf 2>/dev/null || true

###############################################################################
# 5 — Health check file
###############################################################################
echo "healthy" > /var/www/html/health

###############################################################################
# 6 — Main Website HTML
###############################################################################
cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1.0"/>
  <title>Welcome to ${ENV_UPPER} - AI-Powered Infrastructure Monitoring</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{
      font-family:'Segoe UI',system-ui,sans-serif;
      background:${ENV_BG};
      min-height:100vh;color:#fff;
      display:flex;flex-direction:column;
      align-items:center;justify-content:center;
      padding:40px 20px;
    }
    .top-banner{
      width:100%;max-width:1000px;
      background:rgba(34,197,94,.12);
      border:1px solid rgba(34,197,94,.35);
      border-radius:10px;padding:12px 24px;
      margin-bottom:36px;font-size:13px;
      color:#86efac;text-align:center;
    }
    .top-banner strong{color:#fff}
    .env-pill{
      display:inline-block;
      background:${ENV_COLOR};
      color:#fff;padding:3px 14px;
      border-radius:50px;font-size:12px;
      font-weight:700;letter-spacing:1px;
      margin-left:8px;text-transform:uppercase;
    }
    .hero{text-align:center;max-width:760px;margin-bottom:44px}
    .badge{
      display:inline-block;
      background:rgba(255,255,255,.1);
      border:1px solid ${ENV_BORDER};
      color:${ENV_ACCENT};
      padding:5px 20px;border-radius:50px;
      font-size:12px;letter-spacing:2px;
      text-transform:uppercase;margin-bottom:20px;
    }
    h1{
      font-size:clamp(1.9rem,4.5vw,3rem);
      font-weight:800;line-height:1.15;margin-bottom:16px;
      background:linear-gradient(135deg,#fff 0%,${ENV_ACCENT} 100%);
      -webkit-background-clip:text;-webkit-text-fill-color:transparent;
      background-clip:text;
    }
    .sub{font-size:clamp(.9rem,2vw,1.08rem);color:#94a3b8;line-height:1.8;max-width:600px;margin:0 auto 12px}
    .cards{
      display:grid;
      grid-template-columns:repeat(auto-fit,minmax(200px,1fr));
      gap:16px;max-width:1000px;width:100%;margin-bottom:32px;
    }
    .card{
      background:rgba(255,255,255,.05);
      border:1px solid rgba(255,255,255,.08);
      border-radius:16px;padding:26px 18px;
      transition:transform .3s,border-color .3s;
    }
    .card:hover{transform:translateY(-4px);border-color:${ENV_BORDER}}
    .icon{font-size:2rem;margin-bottom:10px}
    .ct{font-size:.92rem;font-weight:700;color:#e2e8f0;margin-bottom:6px}
    .cd{font-size:.78rem;color:#64748b;line-height:1.55}
    .info-bar{
      display:flex;flex-wrap:wrap;justify-content:center;gap:20px;
      max-width:1000px;width:100%;
      background:rgba(255,255,255,.03);
      border:1px solid rgba(255,255,255,.07);
      border-radius:14px;padding:20px 26px;margin-bottom:24px;
    }
    .ii{text-align:center;min-width:110px}
    .il{font-size:.67rem;text-transform:uppercase;letter-spacing:1.5px;color:#475569;margin-bottom:4px}
    .iv{font-size:.86rem;font-weight:600;color:${ENV_ACCENT};word-break:break-all}
    .dot{display:inline-block;width:8px;height:8px;border-radius:50%;background:#22c55e;margin-right:4px;animation:blink 2s infinite}
    @keyframes blink{0%,100%{opacity:1}50%{opacity:.3}}
    .scale-section{max-width:1000px;width:100%;margin-bottom:24px}
    .scale-title{font-size:.68rem;text-transform:uppercase;letter-spacing:2px;color:#475569;text-align:center;margin-bottom:10px}
    .scale-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(185px,1fr));gap:9px}
    .sr{display:flex;align-items:center;gap:10px;background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.06);border-radius:9px;padding:12px 14px}
    .sp{font-size:.95rem;font-weight:800;min-width:50px}
    .sp.g{color:#22c55e}.sp.y{color:#eab308}.sp.o{color:#f97316}.sp.r{color:#ef4444}
    .st{font-size:.76rem;color:#94a3b8;line-height:1.4}
    .st strong{color:#e2e8f0}
    footer{font-size:.7rem;color:#334155;text-align:center;margin-top:4px}
  </style>
</head>
<body>

  <div class="top-banner">
    <strong>✅ This webpage is configured on EC2 instances</strong>
    &nbsp;·&nbsp; Environment: <span class="env-pill">${ENV_UPPER}</span>
    &nbsp;·&nbsp; Served by Apache httpd
    &nbsp;·&nbsp; Registered with Application Load Balancer
    &nbsp;·&nbsp; Managed by Auto Scaling Group (min=1, max=8)
  </div>

  <div class="hero">
    <div class="badge">🤖 ${ENV_UPPER} Environment</div>
    <h1>Welcome to ${ENV_UPPER} AI-Powered<br/>Infrastructure Monitoring</h1>
    <p class="sub">
      Make Your Infrastructure Feel Fantastic with AI-Driven Insights,
      Smart Automation, and Real-Time Observability.
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
      <div class="cd">Live dashboards via Prometheus and Grafana</div>
    </div>
    <div class="card">
      <div class="icon">⚡</div>
      <div class="ct">Auto Scaling</div>
      <div class="cd">CPU and memory-driven scaling — 1 to 8 instances</div>
    </div>
    <div class="card">
      <div class="icon">🌐</div>
      <div class="ct">Application Load Balancer</div>
      <div class="cd">ALB routes traffic across all healthy EC2 instances</div>
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

  <div class="info-bar">
    <div class="ii"><div class="il">Status</div><div class="iv"><span class="dot"></span>Healthy</div></div>
    <div class="ii"><div class="il">Environment</div><div class="iv" id="e-env">…</div></div>
    <div class="ii"><div class="il">Instance ID</div><div class="iv" id="e-iid">…</div></div>
    <div class="ii"><div class="il">Availability Zone</div><div class="iv" id="e-az">…</div></div>
    <div class="ii"><div class="il">Private IP</div><div class="iv" id="e-ip">…</div></div>
    <div class="ii"><div class="il">Region</div><div class="iv" id="e-region">…</div></div>
  </div>

  <div class="scale-section">
    <div class="scale-title">⚡ Auto Scaling Policy — CPU &amp; Memory Thresholds</div>
    <div class="scale-grid">
      <div class="sr"><div class="sp g">≤ 20%</div><div class="st"><strong>Scale In</strong> — remove 1 instance</div></div>
      <div class="sr"><div class="sp y">70–80%</div><div class="st"><strong>Scale Out</strong> — add +1 instance</div></div>
      <div class="sr"><div class="sp o">80–90%</div><div class="st"><strong>Scale Out</strong> — add +2 instances</div></div>
      <div class="sr"><div class="sp r">≥ 90%</div><div class="st"><strong>Scale Out</strong> — add +4 instances (max 8)</div></div>
    </div>
  </div>

  <footer>
    ${ENV_UPPER} · Apache httpd · AWS EC2 · Terraform · Prometheus · Grafana · ALB
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

###############################################################################
# 7 — Info + load-status API (Python on 127.0.0.1:8081)
###############################################################################
mkdir -p /etc/app
cat > /etc/app/env <<ENVFILE
ENVIRONMENT=${environment}
ENV_NAME=${env_name}
AWS_REGION=${aws_region}
INSTANCE_ID=$INSTANCE_ID
AZ=$AZ
PRIVATE_IP=$PRIVATE_IP
INSTANCE_TYPE=$INSTANCE_TYPE
ENVFILE
chmod 600 /etc/app/env

cat > /usr/local/bin/infoserver.py <<'PYEOF'
#!/usr/bin/env python3
import http.server, json, os, subprocess

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/info':
            body = json.dumps({
                "status":        "healthy",
                "environment":   os.getenv("ENVIRONMENT",   "unknown"),
                "env_name":      os.getenv("ENV_NAME",      "unknown"),
                "instance_id":   os.getenv("INSTANCE_ID",  "unknown"),
                "az":            os.getenv("AZ",            "unknown"),
                "private_ip":    os.getenv("PRIVATE_IP",   "unknown"),
                "instance_type": os.getenv("INSTANCE_TYPE","unknown"),
                "region":        os.getenv("AWS_REGION",   "unknown")
            }).encode()
        elif self.path == '/load-status':
            r = subprocess.run(["pgrep","-c","stress-ng"],
                               capture_output=True, text=True)
            running = r.returncode == 0
            body = json.dumps({
                "stress_running": running,
                "process_count":  r.stdout.strip() if running else "0"
            }).encode()
        else:
            body = b'{"error":"not found"}'
        self.send_response(200)
        self.send_header("Content-Type","application/json")
        self.send_header("Access-Control-Allow-Origin","*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a): pass

http.server.HTTPServer(("127.0.0.1", 8081), H).serve_forever()
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

###############################################################################
# 8 — Load test script: /usr/local/bin/load-test.sh
#     Usage: load-test.sh 70   → stress CPU+Memory to ~70%
#            load-test.sh 80   → stress CPU+Memory to ~80%
#            load-test.sh 90   → stress CPU+Memory to ~90%
#            load-test.sh stop → stop all stress processes
###############################################################################
cat > /usr/local/bin/load-test.sh <<'LOADEOF'
#!/bin/bash
###############################################################################
# load-test.sh — Simulate CPU + Memory load to test ASG scaling
# Usage: ./load-test.sh [70|80|90|stop]
###############################################################################
LEVEL=${1:-70}
NCPU=$(nproc)
TOTAL_MEM_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)

case "$LEVEL" in
  stop)
    echo "Stopping all stress-ng processes..."
    pkill -f stress-ng 2>/dev/null || true
    echo "Done. Load stopped."
    exit 0
    ;;
  70)
    CPU_LOAD=70
    MEM_PCT=70
    DURATION=300   # 5 minutes
    ;;
  80)
    CPU_LOAD=80
    MEM_PCT=80
    DURATION=300
    ;;
  90)
    CPU_LOAD=90
    MEM_PCT=90
    DURATION=300
    ;;
  *)
    echo "Usage: $0 [70|80|90|stop]"
    exit 1
    ;;
esac

MEM_MB=$(( TOTAL_MEM_MB * MEM_PCT / 100 ))

echo "========================================================"
echo "  Load Test: $LEVEL%"
echo "  CPUs      : $NCPU cores at $CPU_LOAD% each"
echo "  Memory    : ${MEM_MB}MB / ${TOTAL_MEM_MB}MB ($MEM_PCT%)"
echo "  Duration  : ${DURATION}s"
echo "  Stop with : $0 stop"
echo "========================================================"

# Stop any existing stress
pkill -f stress-ng 2>/dev/null || true
sleep 2

# Run stress in background
nohup stress-ng \
  --cpu   $NCPU \
  --cpu-load $CPU_LOAD \
  --vm 1 \
  --vm-bytes ${MEM_MB}M \
  --timeout ${DURATION}s \
  --metrics-brief \
  > /var/log/load-test.log 2>&1 &

echo "Stress PID: $!"
echo "Monitoring: watch -n5 'cat /proc/loadavg && free -m'"
echo "CloudWatch will detect high CPU/Memory in ~2 minutes"
echo "ASG will scale out automatically"
LOADEOF
chmod +x /usr/local/bin/load-test.sh

###############################################################################
# 9 — CloudWatch Agent config (memory + disk metrics)
###############################################################################
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
          { "file_path": "/var/log/httpd/access_log", "log_group_name": "/aws/ec2/${env_name}/apache/access", "log_stream_name": "{instance_id}" },
          { "file_path": "/var/log/httpd/error_log",  "log_group_name": "/aws/ec2/${env_name}/apache/error",  "log_stream_name": "{instance_id}" }
        ]
      }
    }
  }
}
CWEOF

###############################################################################
# 10 — Start all services
###############################################################################
systemctl daemon-reload
systemctl enable httpd infoserver amazon-cloudwatch-agent
systemctl start  httpd infoserver amazon-cloudwatch-agent

sleep 3
curl -sf http://localhost/health | grep -q healthy \
  && echo "✅ Apache health check: PASSED" \
  || echo "❌ Apache health check: FAILED"

echo "======================================================"
echo " Bootstrap complete : ${env_name}"
echo " Instance           : $INSTANCE_ID"
echo " AZ                 : $AZ"
echo " Website            : http://<ALB-DNS>/"
echo " Health check       : http://<ALB-DNS>/health"
echo " Load test          : sudo load-test.sh [70|80|90|stop]"
echo "======================================================"
