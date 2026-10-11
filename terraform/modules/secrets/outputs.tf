###############################################################################
# Module: secrets — Outputs
###############################################################################

output "secret_arn" {
  description = "ARN of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.db.arn
}

output "secret_name" {
  description = "Name of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.db.name
}

output "db_username" {
  description = "Database master username"
  value       = var.db_username
}

output "read_secret_policy_arn" {
  description = "IAM policy ARN that grants read access to the DB secret"
  value       = aws_iam_policy.read_secret.arn
}
