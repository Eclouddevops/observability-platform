variable "env_name" {
  type = string
}

variable "aws_account_id" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "app_port" {
  type    = number
  default = 80
}

variable "health_check_path" {
  type    = string
  default = "/"
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
