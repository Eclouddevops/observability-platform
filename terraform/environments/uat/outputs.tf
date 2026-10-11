###############################################################################
# UAT Environment — Outputs
###############################################################################

output "environment" {
  value = "uat"
}

output "vpc_id" {
  description = "VPC ID (existing UAT VPC)"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS"
  value       = module.loadbalancer.alb_dns_name
}

output "nlb_dns_name" {
  description = "Network Load Balancer DNS"
  value       = module.loadbalancer.nlb_dns_name
}

output "rds_endpoint" {
  description = "RDS endpoint (sensitive)"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = module.compute.asg_name
}

output "db_secret_arn" {
  description = "Secrets Manager ARN for DB credentials"
  value       = module.secrets.secret_arn
}
