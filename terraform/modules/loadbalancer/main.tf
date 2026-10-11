###############################################################################
# Module: loadbalancer
# Provisions:
#   - Application Load Balancer (ALB) — public-facing, HTTP/HTTPS
#   - Network Load Balancer (NLB)     — public-facing, TCP
#   - Target groups and listeners for both
###############################################################################

locals {
  name_prefix = "${var.project}-${var.environment}"
}

###############################################################################
# ALB Access Log Bucket
###############################################################################
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${local.name_prefix}-alb-access-logs-${var.aws_account_id}"
  force_destroy = var.environment != "prod"

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-alb-access-logs"
    Environment = var.environment
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = data.aws_iam_policy_document.alb_logs.json
}

data "aws_elb_service_account" "main" {}

data "aws_iam_policy_document" "alb_logs" {
  statement {
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs.arn}/alb/AWSLogs/${var.aws_account_id}/*"]
  }
}

###############################################################################
# Application Load Balancer
###############################################################################
resource "aws_lb" "alb" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection
  drop_invalid_header_fields = true

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb"
    enabled = true
  }

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-alb"
    Environment = var.environment
  })
}

###############################################################################
# ALB Target Group
###############################################################################
resource "aws_lb_target_group" "alb" {
  name        = "${local.name_prefix}-alb-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200-299"
  }

  deregistration_delay = 30

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = var.enable_stickiness
  }

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-alb-tg"
    Environment = var.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# ALB HTTP Listener (redirects to HTTPS in production; HTTP in lower envs)
###############################################################################
resource "aws_lb_listener" "alb_http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.https_enabled ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = var.https_enabled ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "forward" {
      for_each = var.https_enabled ? [] : [1]
      content {
        target_group {
          arn = aws_lb_target_group.alb.arn
        }
      }
    }
  }

  tags = merge(var.common_tags, { Environment = var.environment })
}

###############################################################################
# ALB HTTPS Listener (conditional on var.https_enabled)
###############################################################################
resource "aws_lb_listener" "alb_https" {
  count = var.https_enabled ? 1 : 0

  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb.arn
  }

  tags = merge(var.common_tags, { Environment = var.environment })
}

###############################################################################
# Network Load Balancer
###############################################################################
resource "aws_lb" "nlb" {
  name               = "${local.name_prefix}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = var.public_subnet_ids

  enable_deletion_protection       = var.enable_deletion_protection
  enable_cross_zone_load_balancing = true

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-nlb"
    Environment = var.environment
  })
}

###############################################################################
# NLB Target Group
###############################################################################
resource "aws_lb_target_group" "nlb" {
  name        = "${local.name_prefix}-nlb-tg"
  port        = var.nlb_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    protocol            = "TCP"
  }

  deregistration_delay = 30

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-nlb-tg"
    Environment = var.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# NLB Listener
###############################################################################
resource "aws_lb_listener" "nlb" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = var.nlb_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb.arn
  }

  tags = merge(var.common_tags, { Environment = var.environment })
}
