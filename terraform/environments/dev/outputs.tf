###############################################################################
# DEV Environment — Outputs
###############################################################################

output "environment" {
  value = "dev"
}

output "vpc_id" {
  description = "Newly created DEV VPC ID"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}

output "alb_dns_name" {
  value = module.loadbalancer.alb_dns_name
}

output "nlb_dns_name" {
  value = module.loadbalancer.nlb_dns_name
}

output "rds_endpoint" {
  value     = module.rds.db_endpoint
  sensitive = true
}

output "asg_name" {
  value = module.compute.asg_name
}

output "db_secret_arn" {
  value = module.secrets.secret_arn
}
