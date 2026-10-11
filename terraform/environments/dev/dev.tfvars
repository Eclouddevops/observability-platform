###############################################################################
# DEV — ap-south-1 | Account 496251222247
# Resource names: obs-dev-asg, obs-dev-alb, obs-dev-nlb, obs-dev-postgres
###############################################################################

aws_region     = "ap-south-1"
aws_account_id = "496251222247"

# New VPC — fully isolated from UAT
vpc_cidr             = "10.1.0.0/16"
availability_zones   = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
public_subnet_cidrs  = ["10.1.10.0/24", "10.1.11.0/24", "10.1.12.0/24"]
private_subnet_cidrs = ["10.1.20.0/24", "10.1.21.0/24", "10.1.22.0/24"]

# Compute
instance_type        = "t3.micro"
ami_id               = ""
asg_desired_capacity = 1
asg_min_size         = 1
asg_max_size         = 8
app_port             = 80
health_check_path    = "/health"

# RDS
rds_instance_class    = "db.t3.micro"
allocated_storage     = 20
backup_retention_days = 1
db_name               = "appdb"
db_username           = "dbadmin"
