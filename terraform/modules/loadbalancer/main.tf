###############################################################################
# Module: loadbalancer — ALB + NLB + target groups + listeners
###############################################################################

# ALB access log S3 bucket
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.env_name}-alb-logs-${var.aws_account_id}"
  force_destroy = true
  tags          = merge(var.common_tags, { Name = "${var.env_name}-alb-logs" })
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    id     = "expire-90-days"
    status = "Enabled"
    filter {}
    expiration { days = 90 }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = data.aws_elb_service_account.main.arn }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.alb_logs.arn}/alb/AWSLogs/${var.aws_account_id}/*"
    }]
  })
}

# ── Application Load Balancer ─────────────────────────────────────────────────
resource "aws_lb" "alb" {
  name               = "${var.env_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false
  drop_invalid_header_fields = true

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb"
    enabled = true
  }

  tags = merge(var.common_tags, { Name = "${var.env_name}-alb" })
}

resource "aws_lb_target_group" "alb" {
  name        = "${var.env_name}-alb-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200-499"   # wide matcher — works before app is deployed
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30
  tags = merge(var.common_tags, { Name = "${var.env_name}-alb-tg" })
  lifecycle { create_before_destroy = true }
}

resource "aws_lb_listener" "alb_http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb.arn
  }

  tags = merge(var.common_tags, { Name = "${var.env_name}-alb-listener-http" })
}

# ── Network Load Balancer ─────────────────────────────────────────────────────
resource "aws_lb" "nlb" {
  name               = "${var.env_name}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = var.public_subnet_ids

  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = true

  tags = merge(var.common_tags, { Name = "${var.env_name}-nlb" })
}

resource "aws_lb_target_group" "nlb" {
  name        = "${var.env_name}-nlb-tg"
  port        = var.app_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "TCP"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  deregistration_delay = 30
  tags = merge(var.common_tags, { Name = "${var.env_name}-nlb-tg" })
  lifecycle { create_before_destroy = true }
}

resource "aws_lb_listener" "nlb" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = var.app_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb.arn
  }

  tags = merge(var.common_tags, { Name = "${var.env_name}-nlb-listener" })
}
