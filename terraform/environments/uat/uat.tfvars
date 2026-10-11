###############################################################################
# UAT Environment — Variable Values
# Apply: terraform apply -var-file="uat.tfvars"
###############################################################################

project        = "observability"
aws_region     = "ap-south-1"
aws_account_id = "496251222247"

# ── Networking ───────────────────────────────────────────────────────────────
# EXISTING VPC — do not change
existing_vpc_id    = "vpc-091ee3e5d86345078"
availability_zones = ["ap-south-1a", "ap-south-1b"]

# IMPORTANT: Verify these CIDRs do not overlap with existing subnets in the VPC
# Run: aws ec2 describe-subnets --filters Name=vpc-id,Values=vpc-091ee3e5d86345078
public_subnet_cidrs  = ["10.0.10.0/24", "10.0.11.0/24"]
private_subnet_cidrs = ["10.0.20.0/24", "10.0.21.0/24"]

enable_nat_gateway = true

# ── Compute ──────────────────────────────────────────────────────────────────
instance_type        = "t2.micro"
ami_id               = ""   # empty = latest Amazon Linux 2023
asg_desired_capacity = 4
asg_min_size         = 2
asg_max_size         = 8
app_port             = 8080

# Restrict SSH to your VPN/bastion IP range — never 0.0.0.0/0
ssh_allowed_cidrs = []

# ── Load Balancer ────────────────────────────────────────────────────────────
health_check_path   = "/health"
https_enabled       = false
acm_certificate_arn = ""

# ── RDS ──────────────────────────────────────────────────────────────────────
rds_instance_class      = "db.t3.micro"
postgres_engine_version = "15.4"
postgres_major_version  = "15"
allocated_storage       = 20
multi_az                = false
deletion_protection     = true
skip_final_snapshot     = false
backup_retention_days   = 7
db_name                 = "appdb"
db_username             = "dbadmin"
