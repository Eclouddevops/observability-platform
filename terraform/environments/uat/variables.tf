###############################################################################
# UAT — Variables
###############################################################################

variable "project" {
  description = "Project name used in resource naming"
  type        = string
  default     = "observability"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
  default     = "496251222247"
}

# ── Networking ───────────────────────────────────────────────────────────────

variable "existing_vpc_id" {
  description = "Existing UAT VPC ID (do NOT change)"
  type        = string
  default     = "vpc-091ee3e5d86345078"
}

variable "availability_zones" {
  description = "AZs to distribute subnets across"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for new public subnets (must not conflict with existing subnets)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for new private subnets"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "enable_nat_gateway" {
  description = "Create NAT Gateways for private subnet egress"
  type        = bool
  default     = true
}

# ── Compute ──────────────────────────────────────────────────────────────────

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "ami_id" {
  description = "Custom AMI (leave empty for latest Amazon Linux 2023)"
  type        = string
  default     = ""
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
  description = "Application port"
  type        = number
  default     = 8080
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed SSH (restrict to VPN/bastion)"
  type        = list(string)
  default     = []
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
  default = true
}

variable "skip_final_snapshot" {
  type    = bool
  default = false
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "dbadmin"
}
