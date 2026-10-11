###############################################################################
# Module: compute — Outputs
###############################################################################

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.this.name
}

output "asg_arn" {
  description = "Auto Scaling Group ARN"
  value       = aws_autoscaling_group.this.arn
}

output "launch_template_id" {
  description = "Launch Template ID"
  value       = aws_launch_template.this.id
}

output "launch_template_latest_version" {
  description = "Latest Launch Template version"
  value       = aws_launch_template.this.latest_version
}

output "ec2_iam_role_arn" {
  description = "IAM Role ARN assigned to EC2 instances"
  value       = aws_iam_role.ec2.arn
}

output "ec2_instance_profile_name" {
  description = "IAM instance profile name"
  value       = aws_iam_instance_profile.ec2.name
}
