variable "env_name" {
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
  type = list(string)
}

variable "ec2_sg_id" {
  type = string
}

variable "alb_target_group_arn" {
  type = string
}

variable "nlb_target_group_arn" {
  type = string
}

variable "read_secret_policy_arn" {
  type = string
}

variable "db_secret_name" {
  type = string
}

variable "ami_id" {
  type    = string
  default = ""
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "asg_desired" {
  type    = number
  default = 4
}

variable "asg_min" {
  type    = number
  default = 2
}

variable "asg_max" {
  type    = number
  default = 8
}

variable "app_port" {
  type    = number
  default = 80
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
