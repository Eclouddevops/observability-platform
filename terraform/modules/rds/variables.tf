variable "env_name"            { type = string }
variable "private_subnet_ids"  { type = list(string) }
variable "rds_sg_id"           { type = string }
variable "secret_arn"          { type = string }
variable "instance_class"      { type = string; default = "db.t3.micro" }
variable "allocated_storage"   { type = number; default = 20 }
variable "backup_retention_days" { type = number; default = 1 }
variable "common_tags"         { type = map(string); default = {} }
