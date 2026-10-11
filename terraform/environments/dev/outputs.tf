###############################################################################
# DEV Outputs
# Resource naming pattern: obs-dev-<resource>
###############################################################################

output "environment" {
  value = var.environment
}

output "vpc_id" {
  description = "New DEV VPC ID"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}

output "alb_dns_name" {
  description = "obs-dev-alb DNS name"
  value       = module.loadbalancer.alb_dns_name
}

output "nlb_dns_name" {
  description = "obs-dev-nlb DNS name"
  value       = module.loadbalancer.nlb_dns_name
}

output "asg_name" {
  description = "obs-dev-asg"
  value       = module.compute.asg_name
}

output "rds_endpoint" {
  description = "obs-dev-postgres endpoint (sensitive)"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "db_secret_arn" {
  description = "Secrets Manager ARN for obs-dev DB credentials"
  value       = module.secrets.secret_arn
}

output "db_secret_name" {
  description = "Secret name: obs-dev/rds/primary"
  value       = module.secrets.secret_name
}
