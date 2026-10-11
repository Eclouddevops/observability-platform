###############################################################################
# UAT Environment — Variable Values
# Region  : ap-south-1 (Mumbai)
# Account : 496251222247
# VPC     : EXISTING vpc-091ee3e5d86345078 (never recreated)
#
# CIDR RANGES CHOSEN TO AVOID CONFLICT:
#   Public  subnets: 10.0.100.0/24, 10.0.101.0/24
#   Private subnets: 10.0.110.0/24, 10.0.111.0/24
#   These are in 10.0.96.0/19 range — very unlikely to conflict.
#
# If you still get InvalidSubnet.Range, run this on your server:
#   aws ec2 describe-subnets \
#     --filters Name=vpc-id,Values=vpc-091ee3e5d86345078 \
#     --region ap-south-1 \
#     --query 'Subnets[*].CidrBlock' --output table
# Then pick CIDRs that are NOT in the output.
###############################################################################

project        = "obs"
environment    = "uat"
aws_region     = "ap-south-1"
aws_account_id = "496251222247"

# ── Networking ───────────────────────────────────────────────────────────────
existing_vpc_id    = "vpc-091ee3e5d86345078"
availability_zones = ["ap-south-1a", "ap-south-1b"]

# Using high range to avoid conflicts with existing subnets
public_subnet_cidrs  = ["10.0.100.0/24", "10.0.101.0/24"]
private_subnet_cidrs = ["10.0.110.0/24", "10.0.111.0/24"]

enable_nat_gateway = true

# ── Compute ──────────────────────────────────────────────────────────────────
instance_type        = "t2.micro"
ami_id               = ""
asg_desired_capacity = 4
asg_min_size         = 2
asg_max_size         = 8
app_port             = 8080
ssh_allowed_cidrs    = []

# ── Load Balancer ────────────────────────────────────────────────────────────
health_check_path   = "/health"
https_enabled       = false
acm_certificate_arn = ""

# ── RDS ──────────────────────────────────────────────────────────────────────
rds_instance_class      = "db.t3.micro"
postgres_engine_version = "15.7"
postgres_major_version  = "15"
allocated_storage       = 20
multi_az                = false
deletion_protection     = false
skip_final_snapshot     = true
backup_retention_days   = 7
db_name                 = "appdb"
db_username             = "dbadmin"
