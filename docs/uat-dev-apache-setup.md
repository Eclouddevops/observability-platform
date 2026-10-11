# 🖥️ Apache Setup — obs-uat-ec2 & obs-dev-ec2

> **Goal:** Assign public IPs, install & configure Apache on port 80,
> enable auto-start on reboot, and wire up Prometheus monitoring.

---

## Instance Reference

| Field | UAT | Dev |
|---|---|---|
| **Instance ID** | `i-024f0a74e4a4258ae` | `i-02f4285b93fba9910` |
| **Name tag** | `obs-uat-ec2` | `obs-dev-ec2` |
| **Private IP** | `172.31.60.97` | `10.1.22.109` |
| **Public IP** | ⚠️ Not assigned yet | ⚠️ Not assigned yet |
| **Region** | `us-east-1` | `us-east-1` |

---

## Step 1 — Allocate & Associate Elastic IPs

Each instance needs a public IP. Do this in the **AWS Console**:

### AWS Console Method (recommended)

1. Go to **EC2 → Elastic IPs → Allocate Elastic IP address**
2. Click **Allocate** (leave defaults — Amazon's pool)
3. Select the new EIP → **Actions → Associate Elastic IP address**
4. Select:
   - **Resource type:** Instance
   - **Instance:** `i-024f0a74e4a4258ae` (obs-uat-ec2)
   - **Private IP:** `172.31.60.97`
5. Click **Associate**
6. **Repeat** for `i-02f4285b93fba9910` (obs-dev-ec2) with private IP `10.1.22.109`
7. **Note the two allocated public IPs** — you'll need them in Step 4.

### AWS CLI Method (alternative)

```bash
# Allocate EIP for UAT
UAT_ALLOC=$(aws ec2 allocate-address --domain vpc --region us-east-1 \
  --query 'AllocationId' --output text)
echo "UAT AllocationId: $UAT_ALLOC"

# Associate with UAT instance
aws ec2 associate-address \
  --instance-id i-024f0a74e4a4258ae \
  --allocation-id $UAT_ALLOC \
  --region us-east-1

# Get UAT public IP
UAT_EIP=$(aws ec2 describe-addresses --allocation-ids $UAT_ALLOC \
  --query 'Addresses[0].PublicIp' --output text --region us-east-1)
echo "UAT Public IP: $UAT_EIP"

# ──────────────────────────────────────────────────────────────────

# Allocate EIP for Dev
DEV_ALLOC=$(aws ec2 allocate-address --domain vpc --region us-east-1 \
  --query 'AllocationId' --output text)
echo "DEV AllocationId: $DEV_ALLOC"

# Associate with Dev instance
aws ec2 associate-address \
  --instance-id i-02f4285b93fba9910 \
  --allocation-id $DEV_ALLOC \
  --region us-east-1

# Get Dev public IP
DEV_EIP=$(aws ec2 describe-addresses --allocation-ids $DEV_ALLOC \
  --query 'Addresses[0].PublicIp' --output text --region us-east-1)
echo "Dev Public IP: $DEV_EIP"
```

---

## Step 2 — Open Port 80 in Security Groups

The observability server (and the public) need to reach port 80.

### AWS Console

1. EC2 → **Security Groups**
2. Find the Security Group attached to each instance
3. **Inbound rules → Edit → Add rule:**
   - Type: `HTTP`
   - Protocol: `TCP`
   - Port: `80`
   - Source: `0.0.0.0/0` (public) **or** `54.88.150.33/32` (obs server only)
4. Save

### AWS CLI

```bash
# Get Security Group IDs for both instances
aws ec2 describe-instances \
  --instance-ids i-024f0a74e4a4258ae i-02f4285b93fba9910 \
  --region us-east-1 \
  --query 'Reservations[].Instances[].[InstanceId,SecurityGroups[0].GroupId]' \
  --output table

# Add port 80 to each Security Group (replace sg-XXXXXXXXXX with actual IDs)
aws ec2 authorize-security-group-ingress \
  --group-id sg-XXXXXXXXXX \
  --protocol tcp --port 80 \
  --cidr 0.0.0.0/0 \
  --region us-east-1
```

---

## Step 3 — Run Apache Setup Script

SSH onto the **observability server** (`54.88.150.33`) and run:

```bash
cd /observability-platform
git pull origin main   # or the feature branch

# ── UAT ──────────────────────────────────────────────────────────────
# Option A: SSM (no SSH key needed — requires SSM Agent + IAM role)
bash scripts/setup-apache-env.sh 172.31.60.97 uat ssm

# Option B: SSH with PEM key
bash scripts/setup-apache-env.sh 172.31.60.97 uat ~/.ssh/your-key.pem

# Option B (Amazon Linux): add ec2-user
bash scripts/setup-apache-env.sh 172.31.60.97 uat ~/.ssh/your-key.pem ec2-user

# ── Dev ───────────────────────────────────────────────────────────────
bash scripts/setup-apache-env.sh 10.1.22.109 dev ssm
# or
bash scripts/setup-apache-env.sh 10.1.22.109 dev ~/.ssh/your-key.pem
```

### What the Script Does

| Step | Action |
|------|--------|
| 1 | Detects Ubuntu (`apache2`) or Amazon Linux (`httpd`) |
| 2 | **Installs Apache** if not present |
| 3 | Writes `/etc/apache2/sites-available/uat-website.conf` (port 80 vhost) |
| 4 | Creates `/var/www/html/uat/health.html` → returns HTTP 200 |
| 5 | Runs `systemctl enable apache2` → **starts on every reboot** ✅ |
| 6 | Restarts Apache and verifies HTTP 200 response |
| 7 | Prints the exact YAML block to add to `websites.yml` |

---

## Step 4 — Update Prometheus Target with Real IPs

After the script runs and you have the Elastic IPs, edit:

```
prometheus/targets/websites.yml
```

Replace the placeholders:

```yaml
# UAT
- targets:
    - 'http://<UAT-EIP>/health.html'    # e.g. http://54.123.45.67/health.html
  labels:
    env: uat
    service: website
    instance_id: i-024f0a74e4a4258ae
    name: obs-uat-ec2

# Dev
- targets:
    - 'http://<DEV-EIP>/health.html'    # e.g. http://18.200.1.99/health.html
  labels:
    env: dev
    service: website
    instance_id: i-02f4285b93fba9910
    name: obs-dev-ec2
```

Then commit and push, **or** reload Prometheus directly on the server:

```bash
curl -X POST http://localhost:9090/-/reload && echo "✅ Reloaded"
```

---

## Step 5 — Verify Everything

```bash
# 1. Check Apache is running and enabled on the EC2 instance
ssh ubuntu@<uat-eip> "sudo systemctl status apache2 && sudo systemctl is-enabled apache2"
ssh ubuntu@<dev-eip> "sudo systemctl status apache2 && sudo systemctl is-enabled apache2"

# 2. Test HTTP response from the observability server
curl -I http://<uat-eip>/health.html   # should return: HTTP/1.1 200 OK
curl -I http://<dev-eip>/health.html

# 3. Check Blackbox Exporter probe directly
curl -s "http://localhost:9115/probe?target=http://<uat-eip>/health.html&module=http_2xx" \
  | grep probe_success   # should be: probe_success 1

# 4. Check Prometheus targets UI
# Open: http://54.88.150.33:9090/targets
# → blackbox-http job → obs-uat-ec2 and obs-dev-ec2 should show green "UP"

# 5. Check Grafana dashboard
# Open: http://54.88.150.33:3000
# → Dashboard "🌐 Website & SSL Monitoring" → filter env=uat / env=dev
```

---

## Reboot Verification

After completing setup, test that Apache survives a reboot:

```bash
# Reboot the instance (from AWS Console or CLI)
aws ec2 reboot-instances --instance-ids i-024f0a74e4a4258ae --region us-east-1

# Wait ~60 seconds then verify
curl -I http://<uat-eip>/health.html   # must return 200 after reboot
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `curl: (7) Failed to connect` | Check Security Group — port 80 inbound open? |
| `systemctl: Unit not found` | Re-run `setup-apache-env.sh` — it installs Apache |
| `probe_success 0` in Prometheus | Check port 80 open from obs server IP `54.88.150.33` |
| Apache not starting after reboot | SSH → `sudo systemctl enable apache2 && sudo systemctl start apache2` |
| Wrong HTTP response code | Check `/etc/apache2/sites-available/uat-website.conf` + `sudo apachectl configtest` |

---

*Instance IDs confirmed October 2026 — obs-uat-ec2: `i-024f0a74e4a4258ae` | obs-dev-ec2: `i-02f4285b93fba9910`*
