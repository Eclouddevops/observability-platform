###############################################################################
# Module: networking
# Creates or imports VPC, subnets, IGW, NAT GW, and route tables.
# When use_existing_vpc = true the VPC is looked up via a data source and
# only subnets / route-tables are created (UAT mode).
# When use_existing_vpc = false a brand-new VPC is provisioned (DEV mode).
###############################################################################

locals {
  name_prefix = "${var.project}-${var.environment}"

  # Determine actual VPC id regardless of mode
  vpc_id   = var.use_existing_vpc ? data.aws_vpc.existing[0].id : aws_vpc.this[0].id
  vpc_cidr = var.use_existing_vpc ? data.aws_vpc.existing[0].cidr_block : var.vpc_cidr
}

###############################################################################
# ── Existing VPC (UAT) ──────────────────────────────────────────────────────
###############################################################################
data "aws_vpc" "existing" {
  count = var.use_existing_vpc ? 1 : 0
  id    = var.existing_vpc_id
}

# Read any subnets that already exist inside the existing VPC so we can decide
# whether to create new ones or reuse them.
data "aws_subnets" "existing_public" {
  count = var.use_existing_vpc ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [var.existing_vpc_id]
  }
  tags = {
    Tier = "Public"
  }
}

data "aws_subnets" "existing_private" {
  count = var.use_existing_vpc ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [var.existing_vpc_id]
  }
  tags = {
    Tier = "Private"
  }
}

# Look up the existing Internet Gateway attached to the UAT VPC (if any)
data "aws_internet_gateway" "existing" {
  count = var.use_existing_vpc ? 1 : 0
  filter {
    name   = "attachment.vpc-id"
    values = [var.existing_vpc_id]
  }
}

###############################################################################
# ── New VPC (DEV) ────────────────────────────────────────────────────────────
###############################################################################
resource "aws_vpc" "this" {
  count = var.use_existing_vpc ? 0 : 1

  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-vpc"
    Environment = var.environment
  })
}

###############################################################################
# Internet Gateway — only created for new VPC; UAT reuses existing IGW
###############################################################################
resource "aws_internet_gateway" "this" {
  count  = var.use_existing_vpc ? 0 : 1
  vpc_id = local.vpc_id

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-igw"
    Environment = var.environment
  })
}

locals {
  igw_id = var.use_existing_vpc ? data.aws_internet_gateway.existing[0].id : aws_internet_gateway.this[0].id
}

###############################################################################
# Public Subnets
###############################################################################
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = local.vpc_id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-public-${var.availability_zones[count.index]}"
    Tier        = "Public"
    Environment = var.environment
    "kubernetes.io/role/elb" = "1"   # Future EKS readiness
  })
}

###############################################################################
# Private Subnets
###############################################################################
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = local.vpc_id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-private-${var.availability_zones[count.index]}"
    Tier        = "Private"
    Environment = var.environment
    "kubernetes.io/role/internal-elb" = "1"   # Future EKS readiness
  })
}

###############################################################################
# NAT Gateway (one per AZ for HA)
###############################################################################
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? length(var.public_subnet_cidrs) : 0
  domain = "vpc"

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-nat-eip-${count.index + 1}"
    Environment = var.environment
  })
}

resource "aws_nat_gateway" "this" {
  count         = var.enable_nat_gateway ? length(var.public_subnet_cidrs) : 0
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-natgw-${count.index + 1}"
    Environment = var.environment
  })

  depends_on = [aws_internet_gateway.this]
}

###############################################################################
# Route Tables — Public
###############################################################################
resource "aws_route_table" "public" {
  vpc_id = local.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = local.igw_id
  }

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-rt-public"
    Environment = var.environment
  })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

###############################################################################
# Route Tables — Private (one per AZ for HA routing through NAT)
###############################################################################
resource "aws_route_table" "private" {
  count  = var.enable_nat_gateway ? length(var.private_subnet_cidrs) : 1
  vpc_id = local.vpc_id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.this[count.index].id
    }
  }

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-rt-private-${count.index + 1}"
    Environment = var.environment
  })
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = var.enable_nat_gateway ? aws_route_table.private[count.index].id : aws_route_table.private[0].id
}

###############################################################################
# VPC Flow Logs
###############################################################################
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/${local.name_prefix}-flow-logs"
  retention_in_days = var.flow_log_retention_days

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-vpc-flow-logs"
    Environment = var.environment
  })
}

resource "aws_iam_role" "vpc_flow_log" {
  name = "${local.name_prefix}-vpc-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "vpc_flow_log" {
  name = "${local.name_prefix}-vpc-flow-log-policy"
  role = aws_iam_role.vpc_flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "this" {
  vpc_id          = local.vpc_id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.vpc_flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn

  tags = merge(var.common_tags, {
    Name        = "${local.name_prefix}-flow-log"
    Environment = var.environment
  })
}
