###############################################################################
# Module: secrets — Variables
###############################################################################

variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "db_identifier" {
  description = "Logical identifier for the database (used in secret name)"
  type        = string
  default     = "primary"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "dbadmin"
}

variable "db_host" {
  description = "RDS endpoint (set after RDS creation)"
  type        = string
  default     = ""
}

variable "db_port" {
  description = "Database port"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "appdb"
}

variable "recovery_window_in_days" {
  description = "Days before secret is permanently deleted after destruction (0 = immediate)"
  type        = number
  default     = 7
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
