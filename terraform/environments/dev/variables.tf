###############################################################################
# DEV — Variables
###############################################################################

variable "project" {
  type    = string
  default = "observability"
}

variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "aws_account_id" {
  type    = string
  default = "496251222247"
}

# ── Networking ───────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR for the NEW DEV VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["ap-south-1a", "ap-south-1b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.10.0/24", "10.1.11.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.20.0/24", "10.1.21.0/24"]
}

variable "enable_nat_gateway" {
  type    = bool
  default = true
}

# ── Compute ──────────────────────────────────────────────────────────────────

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "ami_id" {
  type    = string
  default = ""
}

variable "asg_desired_capacity" {
  type    = number
  default = 4
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 8
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "ssh_allowed_cidrs" {
  type    = list(string)
  default = []
}

# ── Load Balancer ────────────────────────────────────────────────────────────

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "https_enabled" {
  type    = bool
  default = false
}

variable "acm_certificate_arn" {
  type    = string
  default = ""
}

# ── RDS ──────────────────────────────────────────────────────────────────────

variable "rds_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "postgres_engine_version" {
  type    = string
  default = "15.4"
}

variable "postgres_major_version" {
  type    = string
  default = "15"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "deletion_protection" {
  type    = bool
  default = false   # less strict for DEV
}

variable "skip_final_snapshot" {
  type    = bool
  default = true   # DEV can skip
}

variable "backup_retention_days" {
  type    = number
  default = 1
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "dbadmin"
}
