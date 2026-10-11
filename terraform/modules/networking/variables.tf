###############################################################################
# Module: networking — Variables
###############################################################################

variable "project" {
  description = "Project name used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (uat | dev | prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "use_existing_vpc" {
  description = "When true, import an existing VPC by ID (UAT). When false, create a new VPC (DEV)."
  type        = bool
  default     = false
}

variable "existing_vpc_id" {
  description = "ID of the existing VPC to import when use_existing_vpc = true"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for the NEW VPC (used only when use_existing_vpc = false)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to distribute subnets across (at least 2)"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Whether to provision NAT Gateways for private subnet internet access"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "CloudWatch log retention for VPC flow logs (days)"
  type        = number
  default     = 30
}

variable "common_tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default     = {}
}
