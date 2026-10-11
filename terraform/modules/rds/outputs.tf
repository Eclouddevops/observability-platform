###############################################################################
# Module: rds — Outputs
###############################################################################

output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.this.id
}

output "db_endpoint" {
  description = "RDS connection endpoint"
  value       = aws_db_instance.this.address
  sensitive   = true
}

output "db_port" {
  description = "RDS port"
  value       = aws_db_instance.this.port
}

output "db_instance_arn" {
  description = "ARN of the RDS instance"
  value       = aws_db_instance.this.arn
}

output "db_subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.this.name
}
