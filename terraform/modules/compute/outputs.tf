output "asg_name"              { value = aws_autoscaling_group.this.name }
output "asg_arn"               { value = aws_autoscaling_group.this.arn }
output "launch_template_id"    { value = aws_launch_template.this.id }
output "ec2_iam_role_arn"      { value = aws_iam_role.ec2.arn }
