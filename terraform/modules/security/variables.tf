###############################################################################
# Module: security — Variables
###############################################################################

variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where security groups are created"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block (used for NLB ingress rules)"
  type        = string
}

variable "app_port" {
  description = "Application port exposed by EC2 instances"
  type        = number
  default     = 8080
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed SSH access to EC2 (use bastion/VPN CIDR, not 0.0.0.0/0)"
  type        = list(string)
  default     = []
}

variable "common_tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default     = {}
}
