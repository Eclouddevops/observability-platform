#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# setup-apache-env.sh — Check, Install & Configure Apache on UAT/Dev EC2
#
# What this script does (runs REMOTELY on the target EC2):
#   1. Detects if Apache is installed — installs it if not
#   2. Writes an HTTP-only (port 80) virtual host config for the env
#   3. Enables the site and required Apache modules
#   4. Ensures Apache is enabled to start on every reboot (systemctl enable)
#   5. Starts / restarts Apache and verifies it is running
#   6. Prints the public/private IP so you can add it to websites.yml
#
# USAGE (from the observability server or your local machine):
#
#   Via SSH + PEM key:
#     bash scripts/setup-apache-env.sh <host> <env> [ssh-key] [ssh-user]
#
#   Via AWS SSM (no SSH key needed — requires SSM Agent + IAM role on EC2):
#     bash scripts/setup-apache-env.sh <host> <env> ssm
#
# EXAMPLES:
#   bash scripts/setup-apache-env.sh 10.0.1.50  uat ~/.ssh/my-key.pem
#   bash scripts/setup-apache-env.sh 10.0.2.60  dev ~/.ssh/my-key.pem
#   bash scripts/setup-apache-env.sh 10.0.1.50  uat ssm
#   bash scripts/setup-apache-env.sh 10.0.2.60  dev ssm
#   bash scripts/setup-apache-env.sh 10.0.1.50  uat ~/.ssh/my-key.pem ec2-user
#
# ARGUMENTS:
#   $1  HOST    — Public IP, private IP, or hostname of the EC2 instance
#   $2  ENV     — Environment name: uat | dev
#   $3  KEY     — Path to .pem SSH key  OR  "ssm" for AWS SSM
#   $4  USER    — SSH username (default: ubuntu; use ec2-user for Amazon Linux)
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Argument handling ─────────────────────────────────────────────────────
HOST="${1:-}"
ENV_NAME="${2:-}"
KEY="${3:-}"
SSH_USER="${4:-ubuntu}"

usage() {
    echo "Usage: $0 <host> <env: uat|dev> [ssh-key|ssm] [ssh-user]"
    echo ""
    echo "Examples:"
    echo "  $0 10.0.1.50  uat ~/.ssh/my-key.pem"
    echo "  $0 10.0.2.60  dev ~/.ssh/my-key.pem"
    echo "  $0 10.0.1.50  uat ssm"
    echo "  $0 10.0.2.60  dev ssm"
    exit 1
}

[[ -z "$HOST" ]]     && { echo "❌  Missing HOST argument.";    usage; }
[[ -z "$ENV_NAME" ]] && { echo "❌  Missing ENV argument.";     usage; }
[[ "$ENV_NAME" != "uat" && "$ENV_NAME" != "dev" ]] && {
    echo "❌  ENV must be 'uat' or 'dev' (got: $ENV_NAME)"; usage
}

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Apache Setup for ${ENV_NAME^^} EC2 Instance"
echo "  Host    : $HOST"
echo "  Env     : $ENV_NAME"
echo "  Method  : ${KEY:-auto-detect SSH key}"
echo "  User    : $SSH_USER"
echo "════════════════════════════════════════════════════════════"
echo ""

# ── Remote shell script (runs on the EC2 instance) ────────────────────────
# This heredoc is expanded locally; ENV_NAME is substituted before sending.
REMOTE_SCRIPT=$(cat << SCRIPT
#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${ENV_NAME}"

log()  { echo "[\$(date '+%H:%M:%S')] \$*"; }
ok()   { echo "[\$(date '+%H:%M:%S')] ✅  \$*"; }
warn() { echo "[\$(date '+%H:%M:%S')] ⚠️   \$*"; }
fail() { echo "[\$(date '+%H:%M:%S')] ❌  \$*" >&2; exit 1; }

# ── 1. Detect OS / package manager ───────────────────────────────────────
if command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
    APACHE_PKG="apache2"
    APACHE_SVC="apache2"
    SITES_AVAIL="/etc/apache2/sites-available"
    SITES_ENBL="/etc/apache2/sites-enabled"
elif command -v yum &>/dev/null || command -v dnf &>/dev/null; then
    PKG_MGR="yum"
    APACHE_PKG="httpd"
    APACHE_SVC="httpd"
    # RHEL/Amazon Linux uses /etc/httpd/conf.d/ for virtual hosts
    SITES_AVAIL="/etc/httpd/conf.d"
    SITES_ENBL="/etc/httpd/conf.d"
else
    fail "Unsupported OS — cannot detect apt-get or yum/dnf"
fi

log "OS package manager : \$PKG_MGR"
log "Apache service name: \$APACHE_SVC"

# ── 2. Install Apache if missing ─────────────────────────────────────────
if ! command -v apache2 &>/dev/null && ! command -v httpd &>/dev/null; then
    log "Apache not found — installing \$APACHE_PKG ..."
    if [[ "\$PKG_MGR" == "apt" ]]; then
        sudo apt-get update -qq
        sudo apt-get install -y -qq apache2
    else
        sudo yum install -y httpd 2>/dev/null || sudo dnf install -y httpd
    fi
    ok "Apache installed"
else
    ok "Apache already installed"
fi

# ── 3. Write HTTP virtual host config (port 80 only) ─────────────────────
VHOST_FILE="\${SITES_AVAIL}/\${ENV_NAME}-website.conf"
PUBLIC_IP=\$(curl -sf http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null \
            || hostname -I | awk '{print \$1}')
PRIVATE_IP=\$(curl -sf http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null \
            || hostname -I | awk '{print \$1}')
HOSTNAME=\$(hostname -f 2>/dev/null || echo "\${ENV_NAME}-server")

log "Writing virtual host config: \$VHOST_FILE"

sudo tee "\$VHOST_FILE" > /dev/null << VHOST
# ─────────────────────────────────────────────────────────────────────────
# Apache HTTP Virtual Host — \${ENV_NAME^^} Environment
# Generated by setup-apache-env.sh on \$(date)
# ─────────────────────────────────────────────────────────────────────────
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    ServerName  \${PRIVATE_IP}

    DocumentRoot /var/www/html/\${ENV_NAME}

    <Directory /var/www/html/\${ENV_NAME}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    # Health-check endpoint — returns 200 OK with no content
    # Blackbox Exporter probes this to confirm the site is up
    <Location /health>
        SetHandler None
        Require all granted
    </Location>

    ErrorLog  \${APACHE_LOG_DIR}/\${ENV_NAME}-error.log
    CustomLog \${APACHE_LOG_DIR}/\${ENV_NAME}-access.log combined
    LogLevel warn

    # Expose environment name in response headers (helps with debugging)
    Header always set X-Environment "\${ENV_NAME^^}"
    Header always set X-Server-IP   "\${PRIVATE_IP}"
</VirtualHost>
VHOST

ok "Virtual host config written to \$VHOST_FILE"

# ── 4. Create document root + health-check page ───────────────────────────
sudo mkdir -p /var/www/html/\${ENV_NAME}

# Place a minimal health-check file
sudo tee /var/www/html/\${ENV_NAME}/health.html > /dev/null << 'HEALTHFILE'
OK
HEALTHFILE

# Place a default index page (only if missing)
if [[ ! -f /var/www/html/\${ENV_NAME}/index.html ]]; then
sudo tee /var/www/html/\${ENV_NAME}/index.html > /dev/null << INDEXFILE
<!DOCTYPE html>
<html>
<head><title>\${ENV_NAME^^} Environment</title></head>
<body>
  <h1>\${ENV_NAME^^} Website</h1>
  <p>Apache is running on this EC2 instance.</p>
  <p>Host: \${HOSTNAME} | IP: \${PRIVATE_IP}</p>
</body>
</html>
INDEXFILE
fi

ok "Document root ready at /var/www/html/\${ENV_NAME}/"

# ── 5. Enable modules & site (Debian/Ubuntu only) ─────────────────────────
if [[ "\$PKG_MGR" == "apt" ]]; then
    sudo a2enmod rewrite headers 2>/dev/null | grep -v "Module .* already" || true

    # Disable default site to avoid port conflicts
    sudo a2dissite 000-default.conf 2>/dev/null | grep -v "Site .* already" || true

    # Enable our site
    sudo a2ensite "\${ENV_NAME}-website.conf" 2>/dev/null | grep -v "Site .* already" || true

    ok "Apache modules (rewrite, headers) enabled"
    ok "Site \${ENV_NAME}-website.conf enabled"
fi

# ── 6. Enable Apache at boot + start/restart ──────────────────────────────
log "Enabling \$APACHE_SVC to start on reboot (systemctl enable) ..."
sudo systemctl daemon-reload
sudo systemctl enable "\$APACHE_SVC"

# Restart to pick up new config
log "Restarting \$APACHE_SVC ..."
sudo systemctl restart "\$APACHE_SVC"

# ── 7. Verify Apache is running ───────────────────────────────────────────
sleep 2
if sudo systemctl is-active --quiet "\$APACHE_SVC"; then
    ok "\$APACHE_SVC is RUNNING"
else
    fail "\$APACHE_SVC failed to start — check: sudo journalctl -u \$APACHE_SVC -n 30"
fi

# ── 8. Verify HTTP response on port 80 ────────────────────────────────────
log "Testing HTTP response on localhost:80 ..."
HTTP_CODE=\$(curl -sf -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "000")
if [[ "\$HTTP_CODE" =~ ^(200|301|302|403)$ ]]; then
    ok "HTTP check passed — got HTTP \$HTTP_CODE from localhost:80"
else
    warn "Unexpected HTTP code '\$HTTP_CODE' from localhost:80"
    warn "Check: sudo systemctl status \$APACHE_SVC && sudo journalctl -u \$APACHE_SVC -n 20"
fi

# ── 9. Check /health endpoint ─────────────────────────────────────────────
HEALTH_CODE=\$(curl -sf -o /dev/null -w "%{http_code}" http://localhost/health.html 2>/dev/null || echo "000")
if [[ "\$HEALTH_CODE" == "200" ]]; then
    ok "/health.html returned HTTP 200 — Blackbox Exporter probe will succeed"
else
    warn "/health.html returned HTTP \$HEALTH_CODE — probe may fail"
fi

# ── 10. Print summary ─────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅  Apache (\${ENV_NAME^^}) setup complete on \$(hostname)"
echo ""
echo "  Service status : \$(sudo systemctl is-active \$APACHE_SVC)"
echo "  Enabled at boot: \$(sudo systemctl is-enabled \$APACHE_SVC)"
echo "  Document root  : /var/www/html/\${ENV_NAME}/"
echo "  Config file    : \$VHOST_FILE"
echo ""
echo "  Public IP      : \${PUBLIC_IP}"
echo "  Private IP     : \${PRIVATE_IP}"
echo ""
echo "  Health check   : http://\${PUBLIC_IP}/health.html"
echo "  Website        : http://\${PUBLIC_IP}/"
echo ""
echo "  ➜  Add to prometheus/targets/websites.yml:"
echo "     - targets:"
echo "         - 'http://\${PUBLIC_IP}'"
echo "       labels:"
echo "         env: \${ENV_NAME}"
echo "         service: website"
echo "         category: main"
echo "         owner: eclouddevops"
echo "═══════════════════════════════════════════════════════════════"
SCRIPT
)

# ══════════════════════════════════════════════════════════════════════════
# DELIVERY METHOD: SSM
# ══════════════════════════════════════════════════════════════════════════
if [[ "$KEY" == "ssm" ]]; then
    echo ">>> Using AWS SSM (no SSH key required)"
    echo ""

    REGION="${AWS_DEFAULT_REGION:-us-east-1}"

    # Resolve instance ID from IP (try public, then private)
    INSTANCE_ID=$(aws ec2 describe-instances \
        --filters "Name=ip-address,Values=$HOST" \
                  "Name=instance-state-name,Values=running" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text --region "$REGION" 2>/dev/null || echo "None")

    if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
        INSTANCE_ID=$(aws ec2 describe-instances \
            --filters "Name=private-ip-address,Values=$HOST" \
                      "Name=instance-state-name,Values=running" \
            --query "Reservations[0].Instances[0].InstanceId" \
            --output text --region "$REGION" 2>/dev/null || echo "None")
    fi

    [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]] && {
        echo "❌  Cannot find running EC2 instance for IP: $HOST"
        echo "    Check: aws ec2 describe-instances --region $REGION"
        exit 1
    }

    echo "  Instance ID : $INSTANCE_ID"
    echo "  Region      : $REGION"
    echo ""

    # Encode the script into a JSON-safe single command via base64
    ENCODED=$(echo "$REMOTE_SCRIPT" | base64 -w 0)

    COMMAND_ID=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --region "$REGION" \
        --comment "Setup Apache ${ENV_NAME^^} — observability-platform" \
        --parameters "commands=[\"echo '$ENCODED' | base64 -d | sudo bash\"]" \
        --query "Command.CommandId" \
        --output text) || {
            echo "❌  SSM send-command failed."
            echo "    Ensure: SSM Agent running + AmazonSSMManagedInstanceCore IAM policy"
            exit 1
        }

    echo "  SSM Command ID : $COMMAND_ID"
    echo "  Waiting 60 seconds for remote execution ..."
    sleep 60

    STATUS=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$REGION" \
        --query "Status" \
        --output text 2>/dev/null || echo "Unknown")

    OUTPUT=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$REGION" \
        --query "StandardOutputContent" \
        --output text 2>/dev/null || echo "")

    ERR=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$REGION" \
        --query "StandardErrorContent" \
        --output text 2>/dev/null || echo "")

    echo ""
    echo "═══ Remote Output ═══════════════════════════════════════════"
    echo "$OUTPUT"
    [[ -n "$ERR" ]] && { echo ""; echo "═══ STDERR ═══"; echo "$ERR"; }
    echo ""

    if [[ "$STATUS" == "Success" ]]; then
        echo "✅  SSM command completed successfully (Status: $STATUS)"
    else
        echo "⚠️   SSM Status: $STATUS"
        echo "    AWS Console → Systems Manager → Run Command → $COMMAND_ID"
    fi

# ══════════════════════════════════════════════════════════════════════════
# DELIVERY METHOD: SSH
# ══════════════════════════════════════════════════════════════════════════
else
    echo ">>> Using SSH"
    echo ""

    SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes"

    if [[ -n "$KEY" && -f "$KEY" ]]; then
        echo "  Key : $KEY"
        SSH_OPTS="$SSH_OPTS -i $KEY"
    else
        # Auto-detect
        for K in \
            /observability-platform/secrets/*.pem \
            ~/.ssh/*.pem \
            ~/.ssh/id_rsa \
            ~/.ssh/id_ed25519; do
            if [[ -f "$K" ]]; then
                echo "  Auto-detected key: $K"
                SSH_OPTS="$SSH_OPTS -i $K"
                break
            fi
        done
    fi

    echo "  User : $SSH_USER"
    echo "  Host : $HOST"
    echo ""

    # Run the remote script via SSH pipe
    echo "$REMOTE_SCRIPT" | ssh $SSH_OPTS "${SSH_USER}@${HOST}" 'sudo bash -s'
fi

# ══════════════════════════════════════════════════════════════════════════
# POST-SETUP REMINDER
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  POST-SETUP CHECKLIST"
echo ""
echo "  1. ✅  Apache running and enabled at boot"
echo ""
echo "  2. 🔒  Open port 80 in EC2 Security Group"
echo "         AWS Console → EC2 → Security Groups"
echo "         Add Inbound: TCP 80 from 0.0.0.0/0 (public)"
echo "         OR from 54.88.150.33/32 (observability server only)"
echo ""
echo "  3. 📝  Update prometheus/targets/websites.yml"
echo "         Replace the placeholder URL with the actual IP:"
echo ""
if [[ "$ENV_NAME" == "uat" ]]; then
echo "         - targets:"
echo "             - 'http://${HOST}'"
echo "           labels:"
echo "             env: uat"
echo "             service: website"
echo "             category: main"
echo "             owner: eclouddevops"
else
echo "         - targets:"
echo "             - 'http://${HOST}'"
echo "           labels:"
echo "             env: dev"
echo "             service: website"
echo "             category: main"
echo "             owner: eclouddevops"
fi
echo ""
echo "  4. 🔄  Reload Prometheus to pick up new targets:"
echo "         curl -X POST http://localhost:9090/-/reload"
echo ""
echo "  5. 🔎  Verify target in Prometheus UI:"
echo "         http://54.88.150.33:9090/targets"
echo "         → blackbox-http job should show http://${HOST} as UP"
echo "════════════════════════════════════════════════════════════"
