###############################################################################
# DEV Environment — Root Module
#
# Creates a BRAND NEW VPC and all infrastructure from scratch.
# CIDR range 10.1.0.0/16 (does not conflict with UAT 10.0.0.0/x)
###############################################################################

locals {
  environment = "dev"

  common_tags = {
    Project     = var.project
    Environment = local.environment
    ManagedBy   = "terraform"
    CostCenter  = "platform-engineering"
  }
}

###############################################################################
# 1. Networking — brand-new VPC
###############################################################################
module "networking" {
  source = "../../modules/networking"

  project     = var.project
  environment = local.environment
  aws_region  = var.aws_region

  use_existing_vpc     = false
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway

  common_tags = local.common_tags
}

###############################################################################
# 2. Security Groups
###############################################################################
module "security" {
  source = "../../modules/security"

  project     = var.project
  environment = local.environment

  vpc_id            = module.networking.vpc_id
  vpc_cidr          = module.networking.vpc_cidr
  app_port          = var.app_port
  ssh_allowed_cidrs = var.ssh_allowed_cidrs

  common_tags = local.common_tags
}

###############################################################################
# 3. Secrets Manager — RDS credentials
###############################################################################
module "secrets" {
  source = "../../modules/secrets"

  project     = var.project
  environment = local.environment

  db_identifier           = "primary"
  db_username             = var.db_username
  db_name                 = var.db_name
  recovery_window_in_days = 0   # immediate deletion allowed in DEV

  common_tags = local.common_tags
}

###############################################################################
# 4. RDS PostgreSQL
###############################################################################
module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = local.environment

  private_subnet_ids = module.networking.private_subnet_ids
  rds_sg_id          = module.security.rds_sg_id
  db_secret_arn      = module.secrets.secret_arn

  postgres_major_version  = var.postgres_major_version
  postgres_engine_version = var.postgres_engine_version
  rds_instance_class      = var.rds_instance_class
  allocated_storage       = var.allocated_storage
  multi_az                = var.multi_az
  deletion_protection     = var.deletion_protection
  skip_final_snapshot     = var.skip_final_snapshot
  backup_retention_days   = var.backup_retention_days

  common_tags = local.common_tags

  depends_on = [module.secrets]
}

###############################################################################
# 5. Load Balancers (ALB + NLB)
###############################################################################
module "loadbalancer" {
  source = "../../modules/loadbalancer"

  project        = var.project
  environment    = local.environment
  aws_account_id = var.aws_account_id
  aws_region     = var.aws_region

  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
  alb_sg_id         = module.security.alb_sg_id

  app_port            = var.app_port
  nlb_port            = var.app_port
  health_check_path   = var.health_check_path
  https_enabled       = var.https_enabled
  acm_certificate_arn = var.acm_certificate_arn

  common_tags = local.common_tags
}

###############################################################################
# 6. Compute — ASG with Launch Template
###############################################################################
module "compute" {
  source = "../../modules/compute"

  project     = var.project
  environment = local.environment
  aws_region  = var.aws_region

  private_subnet_ids     = module.networking.private_subnet_ids
  ec2_sg_id              = module.security.ec2_sg_id
  alb_target_group_arn   = module.loadbalancer.alb_target_group_arn
  nlb_target_group_arn   = module.loadbalancer.nlb_target_group_arn
  read_secret_policy_arn = module.secrets.read_secret_policy_arn
  db_secret_name         = module.secrets.secret_name

  ami_id        = var.ami_id
  instance_type = var.instance_type

  asg_desired_capacity = var.asg_desired_capacity
  asg_min_size         = var.asg_min_size
  asg_max_size         = var.asg_max_size

  common_tags = local.common_tags
}
