#!/bin/bash
###############################################################################
# deploy.sh — Terraform deployment script for UAT and DEV environments
#
# Usage:
#   ./deploy.sh                  → Interactive menu
#   ./deploy.sh bootstrap        → Run bootstrap only
#   ./deploy.sh uat plan         → Plan UAT
#   ./deploy.sh uat apply        → Apply UAT
#   ./deploy.sh dev plan         → Plan DEV
#   ./deploy.sh dev apply        → Apply DEV
#   ./deploy.sh all apply        → Apply BOTH UAT and DEV (UAT first)
#   ./deploy.sh uat destroy      → Destroy UAT
#   ./deploy.sh dev destroy      → Destroy DEV
###############################################################################

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Colour

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$SCRIPT_DIR/bootstrap"
UAT_DIR="$SCRIPT_DIR/environments/uat"
DEV_DIR="$SCRIPT_DIR/environments/dev"
LOG_DIR="/tmp/terraform-logs"
mkdir -p "$LOG_DIR"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()     { echo -e "${BOLD}${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${BOLD}${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${BOLD}${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${BOLD}${RED}[ERROR]${NC} $*"; exit 1; }
divider() { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

banner() {
  divider
  echo -e "${BOLD}${CYAN}  🚀  Observability Platform — Terraform Deployer${NC}"
  echo -e "${CYAN}  Account : 496251222247  |  Region : ap-south-1${NC}"
  divider
}

# ── Pre-flight checks ─────────────────────────────────────────────────────────
check_deps() {
  log "Checking dependencies..."

  command -v terraform &>/dev/null || error "terraform not found. Install it first:\n  apt-get install terraform"
  command -v aws       &>/dev/null || error "aws CLI not found. Install it first:\n  /tmp/aws/install"

  local tf_version
  tf_version=$(terraform version -json | python3 -c "import sys,json; print(json.load(sys.stdin)['terraform_version'])")
  success "Terraform $tf_version found"

  local aws_version
  aws_version=$(aws --version 2>&1 | awk '{print $1}')
  success "AWS CLI $aws_version found"
}

check_aws_auth() {
  log "Verifying AWS credentials..."

  local identity
  identity=$(aws sts get-caller-identity --output json 2>/dev/null) || \
    error "AWS credentials not configured. Run: aws configure"

  local account
  account=$(echo "$identity" | python3 -c "import sys,json; print(json.load(sys.stdin)['Account'])")
  local arn
  arn=$(echo "$identity" | python3 -c "import sys,json; print(json.load(sys.stdin)['Arn'])")

  if [[ "$account" != "496251222247" ]]; then
    warn "Expected account 496251222247 but got $account"
    read -rp "Continue anyway? (yes/no): " cont
    [[ "$cont" == "yes" ]] || exit 1
  fi

  success "Authenticated as: $arn"
  success "Account: $account | Region: ap-south-1"
}

# ── Bootstrap ─────────────────────────────────────────────────────────────────
run_bootstrap() {
  divider
  log "Running Bootstrap — S3 state bucket + DynamoDB lock table"
  divider

  cd "$BOOTSTRAP_DIR"

  log "Initializing bootstrap..."
  terraform init -no-color

  log "Planning bootstrap..."
  terraform plan -no-color

  echo ""
  warn "This creates: S3 bucket (496251222247-terraform-state) + DynamoDB table (terraform-state-lock)"
  read -rp "Apply bootstrap? (yes/no): " confirm
  [[ "$confirm" == "yes" ]] || { warn "Bootstrap skipped."; return; }

  terraform apply -auto-approve -no-color
  success "Bootstrap complete!"
  divider
}

# ── Core Terraform runner ─────────────────────────────────────────────────────
run_terraform() {
  local env="$1"       # uat | dev
  local action="$2"    # plan | apply | destroy
  local dir tfvars logfile

  case "$env" in
    uat) dir="$UAT_DIR"; tfvars="uat.tfvars" ;;
    dev) dir="$DEV_DIR"; tfvars="dev.tfvars" ;;
    *)   error "Unknown environment: $env. Use: uat | dev" ;;
  esac

  logfile="$LOG_DIR/${env}-${action}-$(date +%Y%m%d-%H%M%S).log"

  divider
  echo -e "${BOLD}  Environment : $(echo "$env" | tr '[:lower:]' '[:upper:]')${NC}"
  echo -e "${BOLD}  Action      : $action${NC}"
  echo -e "${BOLD}  Directory   : $dir${NC}"
  echo -e "${BOLD}  Log file    : $logfile${NC}"
  divider

  cd "$dir"

  # ── Init ────────────────────────────────────────────────────────────────────
  log "[$env] Initializing Terraform..."
  terraform init -no-color 2>&1 | tee -a "$logfile"
  success "[$env] Init complete"

  # ── Validate ────────────────────────────────────────────────────────────────
  log "[$env] Validating configuration..."
  terraform validate -no-color 2>&1 | tee -a "$logfile"
  success "[$env] Validate complete"

  # ── Plan ────────────────────────────────────────────────────────────────────
  log "[$env] Running plan..."
  terraform plan -var-file="$tfvars" -no-color -out="${LOG_DIR}/${env}.tfplan" 2>&1 | tee -a "$logfile"

  if [[ "$action" == "plan" ]]; then
    success "[$env] Plan complete. Review above output."
    echo -e "${YELLOW}  To apply, run: ./deploy.sh $env apply${NC}"
    return
  fi

  # ── Apply ────────────────────────────────────────────────────────────────────
  if [[ "$action" == "apply" ]]; then
    echo ""
    divider
    warn "REVIEW THE PLAN ABOVE BEFORE PROCEEDING"
    divider
    read -rp "Apply changes to $env? (yes/no): " confirm
    [[ "$confirm" == "yes" ]] || { warn "Apply cancelled for $env."; return; }

    log "[$env] Applying... (this takes ~15 minutes, logging to $logfile)"
    terraform apply "${LOG_DIR}/${env}.tfplan" -no-color 2>&1 | tee -a "$logfile"

    success "[$env] Apply complete!"
    echo ""
    log "[$env] Outputs:"
    terraform output -no-color 2>&1 | tee -a "$logfile"
    return
  fi

  # ── Destroy ──────────────────────────────────────────────────────────────────
  if [[ "$action" == "destroy" ]]; then
    echo ""
    divider
    echo -e "${RED}${BOLD}  ⚠️  DESTROY will permanently delete all $env resources!${NC}"
    if [[ "$env" == "uat" ]]; then
      echo -e "${RED}  NOTE: The existing UAT VPC will NOT be destroyed (it pre-exists).${NC}"
    fi
    divider
    read -rp "Type the environment name to confirm destroy ($env): " confirm_env
    [[ "$confirm_env" == "$env" ]] || { warn "Destroy cancelled — name did not match."; return; }

    log "[$env] Destroying resources..."
    terraform destroy -var-file="$tfvars" -auto-approve -no-color 2>&1 | tee -a "$logfile"
    success "[$env] Destroy complete."
    return
  fi
}

# ── Show outputs ──────────────────────────────────────────────────────────────
show_outputs() {
  local env="$1"
  local dir

  case "$env" in
    uat) dir="$UAT_DIR" ;;
    dev) dir="$DEV_DIR" ;;
    *)   error "Unknown environment: $env" ;;
  esac

  divider
  log "[$env] Current Terraform Outputs:"
  divider
  cd "$dir"
  terraform output -no-color
}

# ── Interactive menu ──────────────────────────────────────────────────────────
interactive_menu() {
  banner

  echo ""
  echo -e "${BOLD}  What would you like to do?${NC}"
  echo ""
  echo -e "  ${CYAN}1)${NC} Bootstrap     — Create S3 state bucket + DynamoDB lock"
  echo -e "  ${CYAN}2)${NC} UAT Plan      — Preview UAT changes"
  echo -e "  ${CYAN}3)${NC} UAT Apply     — Deploy UAT environment"
  echo -e "  ${CYAN}4)${NC} DEV Plan      — Preview DEV changes"
  echo -e "  ${CYAN}5)${NC} DEV Apply     — Deploy DEV environment"
  echo -e "  ${CYAN}6)${NC} ALL Apply     — Deploy UAT then DEV"
  echo -e "  ${CYAN}7)${NC} UAT Outputs   — Show UAT resource outputs"
  echo -e "  ${CYAN}8)${NC} DEV Outputs   — Show DEV resource outputs"
  echo -e "  ${CYAN}9)${NC} UAT Destroy   — ⚠️  Destroy UAT resources"
  echo -e "  ${CYAN}10)${NC} DEV Destroy  — ⚠️  Destroy DEV resources"
  echo -e "  ${CYAN}0)${NC} Exit"
  echo ""
  read -rp "  Enter choice [0-10]: " choice

  case "$choice" in
    1)  run_bootstrap ;;
    2)  run_terraform uat plan ;;
    3)  run_terraform uat apply ;;
    4)  run_terraform dev plan ;;
    5)  run_terraform dev apply ;;
    6)
        log "Deploying ALL environments: UAT → DEV"
        run_terraform uat apply
        run_terraform dev apply
        ;;
    7)  show_outputs uat ;;
    8)  show_outputs dev ;;
    9)  run_terraform uat destroy ;;
    10) run_terraform dev destroy ;;
    0)  echo "Exiting."; exit 0 ;;
    *)  error "Invalid choice: $choice" ;;
  esac
}

# ── Entry point ───────────────────────────────────────────────────────────────
banner
check_deps
check_aws_auth

# CLI mode — arguments provided
if [[ $# -ge 1 ]]; then
  case "$1" in
    bootstrap)
      run_bootstrap
      ;;
    uat|dev)
      [[ $# -ge 2 ]] || error "Usage: ./deploy.sh $1 [plan|apply|destroy]"
      run_terraform "$1" "$2"
      ;;
    all)
      [[ $# -ge 2 ]] || error "Usage: ./deploy.sh all [plan|apply]"
      log "Running $2 for ALL environments: UAT → DEV"
      run_terraform uat "$2"
      run_terraform dev "$2"
      ;;
    outputs)
      [[ $# -ge 2 ]] || error "Usage: ./deploy.sh outputs [uat|dev]"
      show_outputs "$2"
      ;;
    *)
      error "Unknown command: $1\nUsage: ./deploy.sh [bootstrap|uat|dev|all|outputs] [plan|apply|destroy]"
      ;;
  esac
else
  # No arguments — show interactive menu
  interactive_menu
fi
