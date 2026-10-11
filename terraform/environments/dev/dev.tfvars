###############################################################################
# DEV Environment — Variable Values
# Apply: terraform apply -var-file="dev.tfvars"
###############################################################################

project        = "observability"
aws_region     = "ap-south-1"
aws_account_id = "496251222247"

# ── Networking ───────────────────────────────────────────────────────────────
# Brand new VPC — CIDR must not overlap with UAT (10.0.0.0/x)
vpc_cidr           = "10.1.0.0/16"
availability_zones = ["ap-south-1a", "ap-south-1b"]

public_subnet_cidrs  = ["10.1.10.0/24", "10.1.11.0/24"]
private_subnet_cidrs = ["10.1.20.0/24", "10.1.21.0/24"]

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
postgres_engine_version = "15.4"
postgres_major_version  = "15"
allocated_storage       = 20
multi_az                = false
deletion_protection     = false
skip_final_snapshot     = true
backup_retention_days   = 1
db_name                 = "appdb"
db_username             = "dbadmin"
