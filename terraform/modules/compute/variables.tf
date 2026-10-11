###############################################################################
# Module: compute — Variables
###############################################################################

variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "private_subnet_ids" {
  description = "Private subnets for ASG instances"
  type        = list(string)
}

variable "ec2_sg_id" {
  description = "Security group for EC2 instances"
  type        = string
}

variable "alb_target_group_arn" {
  description = "ALB target group ARN to attach ASG to"
  type        = string
}

variable "nlb_target_group_arn" {
  description = "NLB target group ARN to attach ASG to (empty string to skip)"
  type        = string
  default     = ""
}

variable "read_secret_policy_arn" {
  description = "IAM policy ARN granting EC2 instances access to the DB secret"
  type        = string
}

variable "db_secret_name" {
  description = "Secrets Manager secret name (passed to user_data)"
  type        = string
}

variable "ami_id" {
  description = "Custom AMI ID. Leave empty to use the latest Amazon Linux 2023."
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "asg_desired_capacity" {
  description = "Desired number of EC2 instances in the ASG"
  type        = number
  default     = 4
}

variable "asg_min_size" {
  description = "Minimum ASG size"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum ASG size"
  type        = number
  default     = 8
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
