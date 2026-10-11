#!/bin/bash
###############################################################################
# run.sh — Master script for UAT + DEV Terraform environments
# Usage:
#   ./run.sh destroy-all     → Destroy DEV then UAT
#   ./run.sh apply-all       → Apply DEV then UAT
#   ./run.sh recreate-all    → Destroy both then Apply both (full reset)
#   ./run.sh apply-dev       → Apply DEV only
#   ./run.sh apply-uat       → Apply UAT only
#   ./run.sh destroy-dev     → Destroy DEV only
#   ./run.sh destroy-uat     → Destroy UAT only
#   ./run.sh status          → Show current AWS resource status
#   ./run.sh outputs         → Show Terraform outputs for both envs
###############################################################################

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_DIR="$SCRIPT_DIR/environments/dev"
UAT_DIR="$SCRIPT_DIR/environments/uat"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="/tmp/terraform-logs"
mkdir -p "$LOG_DIR"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()     { echo -e "${BOLD}${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${BOLD}${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${BOLD}${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${BOLD}${RED}[ERROR]${NC} $*"; exit 1; }
div()     { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

banner() {
  div
  echo -e "${BOLD}${CYAN}   Observability Platform — Terraform Master Script${NC}"
  echo -e "${CYAN}   Account: 496251222247  |  Region: ap-south-1${NC}"
  echo -e "${CYAN}   UAT: obs-uat-*  |  DEV: obs-dev-*${NC}"
  div
}

# ── Pre-flight checks ──────────────────────────────────────────────────────────
check_deps() {
  command -v terraform &>/dev/null || error "terraform not found"
  command -v aws       &>/dev/null || error "aws CLI not found"

  local acct
  acct=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
    || error "AWS credentials not configured. Run: aws configure"

  if [[ "$acct" != "496251222247" ]]; then
    warn "Expected account 496251222247 but got $acct — continue? (yes/no)"
    read -r c; [[ "$c" == "yes" ]] || exit 1
  fi
  ok "AWS authenticated — account: $acct"
}

# ── Fix stale state issues ────────────────────────────────────────────────────
fix_state() {
  local dir="$1"
  local env="$2"
  log "[$env] Checking for stale state..."

  cd "$dir"

  # Untaint ASG if tainted
  if terraform state show module.compute.aws_autoscaling_group.this &>/dev/null; then
    terraform untaint module.compute.aws_autoscaling_group.this 2>/dev/null || true
    ok "[$env] ASG untainted"
  fi

  # Import CloudWatch log group if exists in AWS but not state
  local lg_name="/aws/vpc/obs-${env}-flow-logs"
  if ! terraform state show module.networking.aws_cloudwatch_log_group.flow_logs &>/dev/null; then
    if aws logs describe-log-groups \
        --log-group-name-prefix "$lg_name" \
        --region ap-south-1 \
        --query 'logGroups[0].logGroupName' \
        --output text 2>/dev/null | grep -q "$lg_name"; then
      log "[$env] Importing existing CloudWatch log group..."
      terraform import \
        module.networking.aws_cloudwatch_log_group.flow_logs \
        "$lg_name" 2>/dev/null || true
      ok "[$env] CloudWatch log group imported"
    fi
  fi
}

# ── Destroy one environment ───────────────────────────────────────────────────
destroy_env() {
  local dir="$1"
  local env="$2"
  local tfvars="${env}.tfvars"
  local logfile="$LOG_DIR/${env}-destroy-$(date +%Y%m%d-%H%M%S).log"

  div
  echo -e "${BOLD}${RED}  DESTROY: $env${NC}"
  div

  cd "$dir"
  terraform init -no-color 2>&1 | tail -3

  # Check if there's anything to destroy
  local count
  count=$(terraform state list 2>/dev/null | wc -l || echo 0)
  if [[ "$count" -eq 0 ]]; then
    warn "[$env] No resources in state — skipping destroy"
    return
  fi

  log "[$env] Found $count resources in state — destroying..."

  # Disable deletion protection on RDS if exists
  local rds_id="obs-${env}-postgres"
  if aws rds describe-db-instances \
      --db-instance-identifier "$rds_id" \
      --region ap-south-1 &>/dev/null 2>&1; then
    log "[$env] Disabling RDS deletion protection..."
    aws rds modify-db-instance \
      --db-instance-identifier "$rds_id" \
      --no-deletion-protection \
      --apply-immediately \
      --region ap-south-1 &>/dev/null || true
    sleep 5
  fi

  terraform destroy \
    -var-file="$tfvars" \
    -auto-approve \
    -no-color \
    2>&1 | tee "$logfile"

  ok "[$env] Destroy complete — log: $logfile"
}

# ── Apply one environment ─────────────────────────────────────────────────────
apply_env() {
  local dir="$1"
  local env="$2"
  local tfvars="${env}.tfvars"
  local logfile="$LOG_DIR/${env}-apply-$(date +%Y%m%d-%H%M%S).log"

  div
  echo -e "${BOLD}${GREEN}  APPLY: $env${NC}"
  div

  cd "$dir"

  log "[$env] Initializing..."
  terraform init -no-color 2>&1 | tail -3

  log "[$env] Validating..."
  terraform validate -no-color

  # Fix any stale state before applying
  fix_state "$dir" "$env"
  cd "$dir"

  log "[$env] Planning..."
  terraform plan \
    -var-file="$tfvars" \
    -no-color \
    -out="$LOG_DIR/${env}.tfplan" \
    2>&1 | tee "$LOG_DIR/${env}-plan.log"

  # Show plan summary
  local adds changes destroys
  adds=$(grep -c "will be created" "$LOG_DIR/${env}-plan.log" 2>/dev/null || echo 0)
  destroys=$(grep -c "will be destroyed" "$LOG_DIR/${env}-plan.log" 2>/dev/null || echo 0)

  div
  echo -e "${BOLD}  [$env] Plan: +${adds} to create, ${destroys} to destroy${NC}"
  div

  log "[$env] Applying (this takes ~15 minutes)..."
  terraform apply \
    "$LOG_DIR/${env}.tfplan" \
    -no-color \
    2>&1 | tee "$logfile"

  ok "[$env] Apply complete!"

  div
  log "[$env] Outputs:"
  terraform output -no-color
  div

  # Update Prometheus ALB target files
  update_prometheus_target "$dir" "$env"
}

# ── Update Prometheus ALB target ──────────────────────────────────────────────
update_prometheus_target() {
  local dir="$1"
  local env="$2"
  local targets_dir="$REPO_DIR/prometheus/targets"

  cd "$dir"
  local alb_dns
  alb_dns=$(terraform output -raw alb_dns_name 2>/dev/null || echo "")

  if [[ -z "$alb_dns" ]]; then
    warn "[$env] Could not get ALB DNS — update prometheus/targets/${env}_alb_targets.yml manually"
    return
  fi

  cat > "${targets_dir}/${env}_alb_targets.yml" <<EOF
- targets:
    - "${alb_dns}"
  labels:
    environment: "${env}"
    env_name:    "obs-${env}"
    region:      "ap-south-1"
    tier:        "alb"
    project:     "observability"
EOF

  ok "[$env] Prometheus target updated: ${alb_dns}"

  # Hot-reload Prometheus if running
  if curl -sf http://localhost:9090/-/ready &>/dev/null; then
    curl -sf -XPOST http://localhost:9090/-/reload &>/dev/null || true
    ok "[$env] Prometheus reloaded"
  fi
}

# ── Show AWS resource status ───────────────────────────────────────────────────
show_status() {
  div
  echo -e "${BOLD}  AWS Resource Status — ap-south-1${NC}"
  div

  echo -e "\n${BOLD}EC2 Instances:${NC}"
  aws ec2 describe-instances \
    --region ap-south-1 \
    --filters "Name=instance-state-name,Values=running,pending,stopped" \
    --query 'Reservations[*].Instances[*].{
      Name:Tags[?Key==`Name`]|[0].Value,
      ID:InstanceId,
      State:State.Name,
      Env:Tags[?Key==`Environment`]|[0].Value,
      AZ:Placement.AvailabilityZone,
      Type:InstanceType
    }' --output table 2>/dev/null || echo "  No instances found"

  echo -e "\n${BOLD}Auto Scaling Groups:${NC}"
  aws autoscaling describe-auto-scaling-groups \
    --region ap-south-1 \
    --query 'AutoScalingGroups[?contains(AutoScalingGroupName,`obs-`)].{
      Name:AutoScalingGroupName,
      Desired:DesiredCapacity,
      Min:MinSize,
      Max:MaxSize,
      Running:Instances[?LifecycleState==`InService`]|length(@)
    }' --output table 2>/dev/null || echo "  No ASGs found"

  echo -e "\n${BOLD}Load Balancers:${NC}"
  aws elbv2 describe-load-balancers \
    --region ap-south-1 \
    --query 'LoadBalancers[?contains(LoadBalancerName,`obs-`)].{
      Name:LoadBalancerName,
      Type:Type,
      State:State.Code,
      DNS:DNSName
    }' --output table 2>/dev/null || echo "  No load balancers found"

  echo -e "\n${BOLD}RDS Instances:${NC}"
  aws rds describe-db-instances \
    --region ap-south-1 \
    --query 'DBInstances[?contains(DBInstanceIdentifier,`obs-`)].{
      ID:DBInstanceIdentifier,
      Status:DBInstanceStatus,
      Class:DBInstanceClass,
      Engine:EngineVersion
    }' --output table 2>/dev/null || echo "  No RDS instances found"

  echo -e "\n${BOLD}Secrets:${NC}"
  aws secretsmanager list-secrets \
    --region ap-south-1 \
    --query 'SecretList[?contains(Name,`obs-`)].{Name:Name}' \
    --output table 2>/dev/null || echo "  No secrets found"
}

# ── Show Terraform outputs ─────────────────────────────────────────────────────
show_outputs() {
  div
  echo -e "${BOLD}  DEV Outputs:${NC}"
  div
  cd "$DEV_DIR"
  terraform output -no-color 2>/dev/null || warn "DEV state not found"

  div
  echo -e "${BOLD}  UAT Outputs:${NC}"
  div
  cd "$UAT_DIR"
  terraform output -no-color 2>/dev/null || warn "UAT state not found"
}

# ── Restart observability stack ────────────────────────────────────────────────
restart_stack() {
  div
  log "Restarting Docker observability stack..."
  cd "$REPO_DIR"

  if [[ -f "docker-compose.yml" ]]; then
    docker compose down
    docker compose up -d
    sleep 20

    # Trigger auto-discovery
    if curl -sf http://localhost:9877/health &>/dev/null; then
      curl -sf -XPOST http://localhost:9877/collect &>/dev/null || true
      ok "Auto-discovery triggered"
    fi

    # Reload Prometheus
    if curl -sf http://localhost:9090/-/ready &>/dev/null; then
      curl -sf -XPOST http://localhost:9090/-/reload &>/dev/null || true
      ok "Prometheus reloaded"
    fi

    ok "Stack restarted"
    echo ""
    local ip
    ip=$(curl -s ifconfig.me 2>/dev/null || echo "localhost")
    echo -e "${BOLD}${GREEN}  Grafana: http://${ip}:3000${NC}"
    echo -e "${BOLD}  Login: admin / ChangeMe2024!${NC}"
    echo -e "${BOLD}  Dashboard: 🏗️ UAT & DEV — Terraform Environments${NC}"
  else
    warn "docker-compose.yml not found — skip stack restart"
  fi
}

###############################################################################
# MAIN
###############################################################################
banner
check_deps

case "${1:-help}" in

  # ── Destroy both ────────────────────────────────────────────────────────────
  destroy-all)
    div
    echo -e "${BOLD}${RED}  DESTROY ALL: DEV + UAT${NC}"
    div
    warn "This will destroy ALL resources in both DEV and UAT!"
    read -rp "Type 'destroy' to confirm: " c
    [[ "$c" == "destroy" ]] || { warn "Aborted."; exit 0; }

    destroy_env "$DEV_DIR" "dev"
    destroy_env "$UAT_DIR" "uat"

    div
    ok "All environments destroyed"
    div
    ;;

  # ── Apply both ──────────────────────────────────────────────────────────────
  apply-all)
    apply_env "$DEV_DIR" "dev"
    apply_env "$UAT_DIR" "uat"

    div
    ok "Both environments applied successfully!"
    div

    show_status
    restart_stack
    ;;

  # ── Recreate both (destroy + apply) ─────────────────────────────────────────
  recreate-all)
    div
    echo -e "${BOLD}${RED}  RECREATE ALL: Destroy DEV + UAT, then Apply DEV + UAT${NC}"
    div
    warn "This will DESTROY and RECREATE all resources in both environments!"
    read -rp "Type 'recreate' to confirm: " c
    [[ "$c" == "recreate" ]] || { warn "Aborted."; exit 0; }

    # Step 1: Destroy both
    log "PHASE 1 — Destroying DEV..."
    destroy_env "$DEV_DIR" "dev"

    log "PHASE 2 — Destroying UAT..."
    destroy_env "$UAT_DIR" "uat"

    # Step 2: Apply both
    log "PHASE 3 — Applying DEV..."
    apply_env "$DEV_DIR" "dev"

    log "PHASE 4 — Applying UAT..."
    apply_env "$UAT_DIR" "uat"

    div
    ok "Both environments recreated successfully!"
    div

    show_status
    restart_stack
    ;;

  # ── Individual env operations ────────────────────────────────────────────────
  apply-dev)
    apply_env "$DEV_DIR" "dev"
    restart_stack
    ;;

  apply-uat)
    apply_env "$UAT_DIR" "uat"
    restart_stack
    ;;

  destroy-dev)
    warn "This will destroy ALL DEV resources!"
    read -rp "Type 'destroy' to confirm: " c
    [[ "$c" == "destroy" ]] || { warn "Aborted."; exit 0; }
    destroy_env "$DEV_DIR" "dev"
    ;;

  destroy-uat)
    warn "This will destroy ALL UAT resources!"
    read -rp "Type 'destroy' to confirm: " c
    [[ "$c" == "destroy" ]] || { warn "Aborted."; exit 0; }
    destroy_env "$UAT_DIR" "uat"
    ;;

  # ── Info commands ─────────────────────────────────────────────────────────
  status)
    show_status
    ;;

  outputs)
    show_outputs
    ;;

  # ── Help ──────────────────────────────────────────────────────────────────
  help|*)
    echo ""
    echo -e "${BOLD}Usage:${NC} ./run.sh <command>"
    echo ""
    echo -e "  ${CYAN}recreate-all${NC}   Destroy both envs then recreate both  ← USE THIS"
    echo -e "  ${CYAN}apply-all${NC}      Apply DEV then UAT"
    echo -e "  ${CYAN}destroy-all${NC}    Destroy DEV then UAT"
    echo -e "  ${CYAN}apply-dev${NC}      Apply DEV only"
    echo -e "  ${CYAN}apply-uat${NC}      Apply UAT only"
    echo -e "  ${CYAN}destroy-dev${NC}    Destroy DEV only"
    echo -e "  ${CYAN}destroy-uat${NC}    Destroy UAT only"
    echo -e "  ${CYAN}status${NC}         Show all AWS resources"
    echo -e "  ${CYAN}outputs${NC}        Show Terraform outputs"
    echo ""
    ;;

esac
