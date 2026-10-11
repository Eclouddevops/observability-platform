variable "env_name"            { type = string }   # e.g. obs-uat, obs-dev
variable "use_existing_vpc"    { type = bool;   default = false }
variable "existing_vpc_id"     { type = string; default = "" }
variable "vpc_cidr"            { type = string; default = "10.1.0.0/16" }
variable "availability_zones"  { type = list(string) }
variable "public_subnet_cidrs" { type = list(string) }
variable "private_subnet_cidrs"{ type = list(string) }
variable "enable_nat_gateway"  { type = bool;   default = true }
variable "common_tags"         { type = map(string); default = {} }
