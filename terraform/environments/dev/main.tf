###############################################################################
# DEV Environment
# All resources named: obs-dev-<resource>
# VPC: NEW 10.1.0.0/16 — fully isolated from UAT
###############################################################################

locals {
  env_name = "obs-dev"
  tags = {
    Project     = "observability"
    Environment = "dev"
    EnvName     = local.env_name
    ManagedBy   = "terraform"
    Region      = "ap-south-1"
    CostCenter  = "platform-engineering"
  }
}

module "networking" {
  source               = "../../modules/networking"
  env_name             = local.env_name
  use_existing_vpc     = false
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = true
  common_tags          = local.tags
}

module "security" {
  source      = "../../modules/security"
  env_name    = local.env_name
  vpc_id      = module.networking.vpc_id
  vpc_cidr    = module.networking.vpc_cidr
  app_port    = var.app_port
  common_tags = local.tags
}

module "secrets" {
  source      = "../../modules/secrets"
  env_name    = local.env_name
  db_username = var.db_username
  db_name     = var.db_name
  common_tags = local.tags
}

module "rds" {
  source                = "../../modules/rds"
  env_name              = local.env_name
  private_subnet_ids    = module.networking.private_subnet_ids
  rds_sg_id             = module.security.rds_sg_id
  secret_arn            = module.secrets.secret_arn
  instance_class        = var.rds_instance_class
  allocated_storage     = var.allocated_storage
  backup_retention_days = var.backup_retention_days
  common_tags           = local.tags
  depends_on            = [module.secrets]
}

module "loadbalancer" {
  source            = "../../modules/loadbalancer"
  env_name          = local.env_name
  aws_account_id    = var.aws_account_id
  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
  app_port          = var.app_port
  health_check_path = var.health_check_path
  common_tags       = local.tags
}

module "compute" {
  source                 = "../../modules/compute"
  env_name               = local.env_name
  environment            = "dev"
  aws_region             = var.aws_region
  private_subnet_ids     = module.networking.private_subnet_ids
  ec2_sg_id              = module.security.ec2_sg_id
  alb_target_group_arn   = module.loadbalancer.alb_target_group_arn
  nlb_target_group_arn   = module.loadbalancer.nlb_target_group_arn
  read_secret_policy_arn = module.secrets.read_secret_policy_arn
  db_secret_name         = module.secrets.secret_name
  instance_type          = var.instance_type
  ami_id                 = var.ami_id
  asg_desired            = var.asg_desired_capacity
  asg_min                = var.asg_min_size
  asg_max                = var.asg_max_size
  app_port               = var.app_port
  common_tags            = local.tags
}
