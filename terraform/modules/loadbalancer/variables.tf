###############################################################################
# Module: loadbalancer — Variables
###############################################################################

variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_account_id" {
  description = "AWS account ID (used for S3 bucket naming)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "Public subnets for ALB and NLB"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group for ALB"
  type        = string
}

variable "app_port" {
  description = "Application port for ALB target group"
  type        = number
  default     = 8080
}

variable "nlb_port" {
  description = "TCP port for NLB target group"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "HTTP path for ALB health check"
  type        = string
  default     = "/health"
}

variable "https_enabled" {
  description = "Enable HTTPS listener on ALB (requires acm_certificate_arn)"
  type        = bool
  default     = false
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener"
  type        = string
  default     = ""
}

variable "enable_stickiness" {
  description = "Enable session stickiness on ALB target group"
  type        = bool
  default     = false
}

variable "enable_deletion_protection" {
  description = "Protect ALB and NLB from accidental deletion"
  type        = bool
  default     = false
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
