###############################################################################
# Module: security — Outputs
###############################################################################

output "alb_sg_id" {
  description = "Security group ID for the Application Load Balancer"
  value       = aws_security_group.alb.id
}

output "nlb_target_sg_id" {
  description = "Security group ID for NLB targets"
  value       = aws_security_group.nlb_target.id
}

output "ec2_sg_id" {
  description = "Security group ID for EC2 / ASG instances"
  value       = aws_security_group.ec2.id
}

output "rds_sg_id" {
  description = "Security group ID for RDS instances"
  value       = aws_security_group.rds.id
}
