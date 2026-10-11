variable "env_name" {
  type = string
}

variable "db_username" {
  type    = string
  default = "dbadmin"
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
