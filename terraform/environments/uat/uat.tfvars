###############################################################################
# UAT — ap-south-1 | Account 496251222247
# Resource names: obs-uat-asg, obs-uat-alb, obs-uat-nlb, obs-uat-postgres
#
# Subnets use 10.0.100-111.x range to avoid conflict with existing VPC subnets
###############################################################################

aws_region     = "ap-south-1"
aws_account_id = "496251222247"

# Existing VPC — never recreated
existing_vpc_id      = "vpc-091ee3e5d86345078"
availability_zones   = ["ap-south-1a", "ap-south-1b"]
public_subnet_cidrs  = ["10.0.100.0/24", "10.0.101.0/24"]
private_subnet_cidrs = ["10.0.110.0/24", "10.0.111.0/24"]

# Compute
instance_type        = "t2.micro"
ami_id               = ""
asg_desired_capacity = 4
asg_min_size         = 2
asg_max_size         = 8
app_port             = 80
health_check_path    = "/"

# RDS
rds_instance_class    = "db.t3.micro"
allocated_storage     = 20
backup_retention_days = 7
db_name               = "appdb"
db_username           = "dbadmin"
