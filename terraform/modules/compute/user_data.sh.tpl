#!/bin/bash
set -euo pipefail

# ── Bootstrap EC2 instance ──────────────────────────────────────────────────
# Environment : ${environment}
# Project     : ${project}
# Region      : ${aws_region}
# DB Secret   : ${db_secret_name}
# ──────────────────────────────────────────────────────────────────────────────

# Update and install packages
dnf update -y
dnf install -y amazon-cloudwatch-agent jq aws-cli

# Install CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCONFIG'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/${project}/${environment}/var/log/messages",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/app/*.log",
            "log_group_name": "/${project}/${environment}/app",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "${project}/${environment}",
    "metrics_collected": {
      "mem": { "measurement": ["mem_used_percent"] },
      "disk": { "measurement": ["disk_used_percent"] }
    }
  }
}
CWCONFIG

systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Fetch DB credentials from Secrets Manager
DB_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "${db_secret_name}" \
  --region "${aws_region}" \
  --query SecretString \
  --output text)

DB_HOST=$(echo "$DB_SECRET" | jq -r '.host')
DB_USER=$(echo "$DB_SECRET" | jq -r '.username')
DB_PASS=$(echo "$DB_SECRET" | jq -r '.password')
DB_NAME=$(echo "$DB_SECRET" | jq -r '.dbname')

# Export as environment variables for the application
mkdir -p /etc/app
cat > /etc/app/env <<ENVFILE
DB_HOST=$DB_HOST
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASS
DB_NAME=$DB_NAME
AWS_REGION=${aws_region}
ENVIRONMENT=${environment}
ENVFILE

chmod 600 /etc/app/env

echo "Bootstrap complete for ${project}/${environment} on $(hostname)"
