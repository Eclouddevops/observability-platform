###############################################################################
# Module: secrets — auto-generated DB password in Secrets Manager
###############################################################################

resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%&*-_=+?"
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.env_name}/rds/primary"
  description             = "RDS credentials for ${var.env_name}"
  recovery_window_in_days = 0   # immediate delete — allows clean destroy
  tags                    = merge(var.common_tags, { Name = "${var.env_name}/rds/primary" })
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    engine   = "postgres"
    port     = 5432
    dbname   = var.db_name
    host     = ""   # updated by RDS module after instance is created
  })
}

# IAM policy — EC2 instances read ONLY this secret
data "aws_iam_policy_document" "read_secret" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.db.arn]
  }
}

resource "aws_iam_policy" "read_secret" {
  name   = "${var.env_name}-read-db-secret"
  policy = data.aws_iam_policy_document.read_secret.json
  tags   = var.common_tags
}
