###############################################################################
# Module: secrets
# Stores RDS credentials in AWS Secrets Manager.
# A random password is generated on first apply; never hardcoded.
###############################################################################

locals {
  name_prefix   = "${var.project}-${var.environment}"
  secret_name   = "${local.name_prefix}/rds/${var.db_identifier}"
}

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"  # excludes @, /, " which break pg conn strings
}

resource "aws_secretsmanager_secret" "db" {
  name                    = local.secret_name
  description             = "RDS PostgreSQL credentials for ${local.name_prefix}"
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.common_tags, {
    Name        = local.secret_name
    Environment = var.environment
  })
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    engine   = "postgres"
    host     = var.db_host      # populated after RDS is created (use depends_on)
    port     = var.db_port
    dbname   = var.db_name
  })
}

###############################################################################
# IAM policy allowing EC2 instances to read only this secret
###############################################################################
data "aws_iam_policy_document" "read_secret" {
  statement {
    sid    = "AllowReadSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [aws_secretsmanager_secret.db.arn]
  }
}

resource "aws_iam_policy" "read_secret" {
  name        = "${local.name_prefix}-read-db-secret"
  description = "Allow reading the RDS secret for ${local.name_prefix}"
  policy      = data.aws_iam_policy_document.read_secret.json
  tags        = var.common_tags
}
