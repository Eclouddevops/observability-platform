output "vpc_id" {
  value = local.vpc_id
}

output "vpc_cidr" {
  value = local.vpc_cidr
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "nat_gateway_ids" {
  value = aws_nat_gateway.this[*].id
}
