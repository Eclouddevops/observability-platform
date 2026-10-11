###############################################################################
# Module: rds
# Provisions Amazon RDS for PostgreSQL inside private subnets.
# Credentials are pulled from AWS Secrets Manager (never hardcoded).
###############################################################################

locals {
  name_prefix = "${var.project}-${var.environment}"
}

###############################################################################
# DB Subnet Group — requires subnets in at least 2 AZs
###############################################################################
resource "aws_db_subnet_group" "this" {
  name        = "${local.name_prefix}-db-subnet-group"
  description = "Private subnet group for ${local.name_prefix} RDS"
  subnet_ids  = var.private_subnet_ids

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-db-subnet-group"
    Environment = var.environment
  })
}

###############################################################################
# DB Parameter Group
###############################################################################
resource "aws_db_parameter_group" "this" {
  name        = "${local.name_prefix}-pg-params"
  family      = "postgres${var.postgres_major_version}"
  description = "Custom parameters for ${local.name_prefix} PostgreSQL"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"   # log queries > 1 second
  }

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-pg-params"
    Environment = var.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# Fetch DB password from Secrets Manager at plan time
###############################################################################
data "aws_secretsmanager_secret" "db" {
  arn = var.db_secret_arn
}

data "aws_secretsmanager_secret_version" "db" {
  secret_id = data.aws_secretsmanager_secret.db.id
}

locals {
  db_creds = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string)
}

###############################################################################
# RDS Instance
###############################################################################
resource "aws_db_instance" "this" {
  identifier        = "${local.name_prefix}-postgres"
  engine            = "postgres"
  engine_version    = var.postgres_engine_version
  instance_class    = var.rds_instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = var.kms_key_arn   # null = AWS managed key

  db_name  = local.db_creds["dbname"]
  username = local.db_creds["username"]
  password = local.db_creds["password"]

  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = [var.rds_sg_id]

  multi_az               = var.multi_az
  publicly_accessible    = false
  deletion_protection    = var.deletion_protection
  skip_final_snapshot    = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name_prefix}-final-snapshot"

  backup_retention_period = var.backup_retention_days
  backup_window           = "02:00-03:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  auto_minor_version_upgrade = true
  apply_immediately          = false   # avoid unplanned restarts in production

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-postgres"
    Environment = var.environment
  })
}

###############################################################################
# Update Secrets Manager with the actual endpoint (idempotent update)
###############################################################################
resource "aws_secretsmanager_secret_version" "update_host" {
  secret_id = var.db_secret_arn
  secret_string = jsonencode({
    username = local.db_creds["username"]
    password = local.db_creds["password"]
    engine   = "postgres"
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    dbname   = local.db_creds["dbname"]
  })

  depends_on = [aws_db_instance.this]
}
