output "secret_arn" {
  value = aws_secretsmanager_secret.db.arn
}

output "secret_name" {
  value = aws_secretsmanager_secret.db.name
}

output "db_username" {
  value = var.db_username
}

output "read_secret_policy_arn" {
  value = aws_iam_policy.read_secret.arn
}
