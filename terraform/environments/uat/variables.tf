variable "aws_region"     { type = string; default = "ap-south-1" }
variable "aws_account_id" { type = string; default = "496251222247" }

variable "existing_vpc_id"      { type = string; default = "vpc-091ee3e5d86345078" }
variable "availability_zones"   { type = list(string); default = ["ap-south-1a", "ap-south-1b"] }
variable "public_subnet_cidrs"  { type = list(string); default = ["10.0.100.0/24", "10.0.101.0/24"] }
variable "private_subnet_cidrs" { type = list(string); default = ["10.0.110.0/24", "10.0.111.0/24"] }

variable "instance_type"        { type = string; default = "t2.micro" }
variable "ami_id"               { type = string; default = "" }
variable "asg_desired_capacity" { type = number; default = 4 }
variable "asg_min_size"         { type = number; default = 2 }
variable "asg_max_size"         { type = number; default = 8 }
variable "app_port"             { type = number; default = 80 }
variable "health_check_path"    { type = string; default = "/" }

variable "rds_instance_class"   { type = string; default = "db.t3.micro" }
variable "allocated_storage"    { type = number; default = 20 }
variable "backup_retention_days"{ type = number; default = 7 }
variable "db_name"              { type = string; default = "appdb" }
variable "db_username"          { type = string; default = "dbadmin" }
