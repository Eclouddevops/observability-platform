###############################################################################
# Module: security
# Creates least-privilege security groups for ALB, NLB, EC2, and RDS.
###############################################################################

locals {
  name_prefix = "${var.project}-${var.environment}"
}

###############################################################################
# ALB Security Group — allows HTTP/HTTPS from internet
###############################################################################
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-sg-alb"
  description = "ALB - allow HTTP/HTTPS from internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-sg-alb"
    Environment = var.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# NLB does not use Security Groups (NLBs use Network ACLs / target SGs)
# We define a security group for NLB targets / cross-reference
###############################################################################
resource "aws_security_group" "nlb_target" {
  name        = "${local.name_prefix}-sg-nlb-target"
  description = "NLB target - allow TCP traffic from NLB"
  vpc_id      = var.vpc_id

  ingress {
    description = "App port from NLB (health + traffic)"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-sg-nlb-target"
    Environment = var.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# EC2 / ASG Security Group
###############################################################################
resource "aws_security_group" "ec2" {
  name        = "${local.name_prefix}-sg-ec2"
  description = "EC2 instances - allow traffic from ALB and NLB only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "App port from NLB (by VPC CIDR as NLBs preserve source IPs)"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "SSH from bastion / VPN CIDR only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-sg-ec2"
    Environment = var.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# RDS Security Group — only EC2 SG may connect
###############################################################################
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-sg-rds"
  description = "RDS PostgreSQL - allow access from EC2 SG only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-sg-rds"
    Environment = var.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}
