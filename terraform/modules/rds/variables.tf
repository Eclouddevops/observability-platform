###############################################################################
# Module: rds — Variables
###############################################################################

variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the DB subnet group (min 2 AZs)"
  type        = list(string)
}

variable "rds_sg_id" {
  description = "Security group ID for RDS"
  type        = string
}

variable "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials"
  type        = string
}

variable "postgres_major_version" {
  description = "Major version of PostgreSQL for the parameter group family (e.g. 15)"
  type        = string
  default     = "15"
}

variable "postgres_engine_version" {
  description = "Full PostgreSQL engine version string (e.g. 15.4)"
  type        = string
  default     = "15.4"
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Enable Multi-AZ for high availability"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Prevent accidental deletion"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on destroy (set false for production)"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
}

variable "kms_key_arn" {
  description = "KMS key ARN for storage encryption (null = AWS managed key)"
  type        = string
  default     = null
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
