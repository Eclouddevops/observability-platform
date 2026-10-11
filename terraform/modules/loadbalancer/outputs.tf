###############################################################################
# Module: loadbalancer — Outputs
###############################################################################

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.alb.arn
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.alb.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB (for Route53 alias records)"
  value       = aws_lb.alb.zone_id
}

output "alb_target_group_arn" {
  description = "ARN of the ALB target group"
  value       = aws_lb_target_group.alb.arn
}

output "nlb_arn" {
  description = "ARN of the Network Load Balancer"
  value       = aws_lb.nlb.arn
}

output "nlb_dns_name" {
  description = "DNS name of the NLB"
  value       = aws_lb.nlb.dns_name
}

output "nlb_zone_id" {
  description = "Hosted zone ID of the NLB"
  value       = aws_lb.nlb.zone_id
}

output "nlb_target_group_arn" {
  description = "ARN of the NLB target group"
  value       = aws_lb_target_group.nlb.arn
}
