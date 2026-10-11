###############################################################################
# Module: networking — Outputs
###############################################################################

output "vpc_id" {
  description = "ID of the VPC (existing or newly created)"
  value       = local.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = local.vpc_cidr
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = local.igw_id
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs (empty if enable_nat_gateway = false)"
  value       = aws_nat_gateway.this[*].id
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "IDs of the private route tables"
  value       = aws_route_table.private[*].id
}

output "availability_zones" {
  description = "AZs used by subnets"
  value       = var.availability_zones
}
