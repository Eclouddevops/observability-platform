###############################################################################
# Module: rds — PostgreSQL in private subnets
# Uses postgres 16.3 — widely available in all AWS regions including ap-south-1
###############################################################################

resource "aws_db_subnet_group" "this" {
  name        = "${var.env_name}-db-subnet-group"
  description = "Private subnets for ${var.env_name} RDS"
  subnet_ids  = var.private_subnet_ids
  tags        = merge(var.common_tags, { Name = "${var.env_name}-db-subnet-group" })
}

resource "aws_db_parameter_group" "this" {
  name        = "${var.env_name}-pg16-params"
  family      = "postgres16"
  description = "Custom params for ${var.env_name}"

  parameter {
    name  = "log_connections"
    value = "1"
  }
  parameter {
    name  = "log_disconnections"
    value = "1"
  }
  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"
    apply_method = "immediate"
  }

  tags = merge(var.common_tags, { Name = "${var.env_name}-pg16-params" })

  lifecycle { create_before_destroy = true }
}

# Read credentials from Secrets Manager
data "aws_secretsmanager_secret_version" "db" {
  secret_id = var.secret_arn
}

locals {
  creds = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string)
}

resource "aws_db_instance" "this" {
  # Naming
  identifier = "${var.env_name}-postgres"

  # Engine — postgres 16.9 confirmed available in ap-south-1
  engine         = "postgres"
  engine_version = "16.9"
  instance_class = var.instance_class

  # Storage
  allocated_storage = var.allocated_storage
  storage_type      = "gp2"       # gp2 avoids gp3 IOPS issues on t3.micro
  storage_encrypted = true

  # Credentials from Secrets Manager
  db_name  = local.creds["dbname"]
  username = local.creds["username"]
  password = local.creds["password"]

  # Network
  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = false

  # Lifecycle
  multi_az                = false
  deletion_protection     = false
  skip_final_snapshot     = true
  delete_automated_backups = true

  # Backup
  backup_retention_period = var.backup_retention_days
  backup_window           = "02:00-03:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Monitoring
  enabled_cloudwatch_logs_exports       = ["postgresql"]
  performance_insights_enabled          = false  # not supported on t3.micro free tier
  auto_minor_version_upgrade            = true
  apply_immediately                     = true

  tags = merge(var.common_tags, { Name = "${var.env_name}-postgres" })
}

# Update secret with real RDS endpoint after creation
resource "aws_secretsmanager_secret_version" "update_host" {
  secret_id = var.secret_arn
  secret_string = jsonencode({
    username = local.creds["username"]
    password = local.creds["password"]
    engine   = "postgres"
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    dbname   = local.creds["dbname"]
  })
  depends_on = [aws_db_instance.this]
}
