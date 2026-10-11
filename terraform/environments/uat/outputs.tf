output "env_name"          { value = "obs-uat" }
output "vpc_id"            { value = module.networking.vpc_id }
output "public_subnets"    { value = module.networking.public_subnet_ids }
output "private_subnets"   { value = module.networking.private_subnet_ids }
output "alb_dns_name"      { value = module.loadbalancer.alb_dns_name }
output "nlb_dns_name"      { value = module.loadbalancer.nlb_dns_name }
output "asg_name"          { value = module.compute.asg_name }
output "rds_identifier"    { value = module.rds.db_identifier }
output "rds_endpoint"      { value = module.rds.db_endpoint; sensitive = true }
output "db_secret_name"    { value = module.secrets.secret_name }
output "db_secret_arn"     { value = module.secrets.secret_arn }
