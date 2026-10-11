###############################################################################
# Module: networking
# UAT  → use_existing_vpc = true  → reuses vpc-091ee3e5d86345078
# DEV  → use_existing_vpc = false → creates new VPC 10.1.0.0/16
###############################################################################

locals {
  vpc_id   = var.use_existing_vpc ? data.aws_vpc.existing[0].id : aws_vpc.this[0].id
  vpc_cidr = var.use_existing_vpc ? data.aws_vpc.existing[0].cidr_block : var.vpc_cidr
  igw_id   = var.use_existing_vpc ? data.aws_internet_gateway.existing[0].id : aws_internet_gateway.this[0].id
}

# ── Existing VPC lookup (UAT only) ───────────────────────────────────────────
data "aws_vpc" "existing" {
  count = var.use_existing_vpc ? 1 : 0
  id    = var.existing_vpc_id
}

data "aws_internet_gateway" "existing" {
  count = var.use_existing_vpc ? 1 : 0
  filter {
    name   = "attachment.vpc-id"
    values = [var.existing_vpc_id]
  }
}

# ── New VPC (DEV only) ───────────────────────────────────────────────────────
resource "aws_vpc" "this" {
  count                = var.use_existing_vpc ? 0 : 1
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(var.common_tags, { Name = "${var.env_name}-vpc" })
}

resource "aws_internet_gateway" "this" {
  count  = var.use_existing_vpc ? 0 : 1
  vpc_id = aws_vpc.this[0].id
  tags   = merge(var.common_tags, { Name = "${var.env_name}-igw" })
}

# ── Public Subnets ────────────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = local.vpc_id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = merge(var.common_tags, {
    Name = "${var.env_name}-public-${count.index + 1}"
    Tier = "Public"
  })
}

# ── Private Subnets ───────────────────────────────────────────────────────────
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = local.vpc_id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = merge(var.common_tags, {
    Name = "${var.env_name}-private-${count.index + 1}"
    Tier = "Private"
  })
}

# ── Elastic IPs for NAT ───────────────────────────────────────────────────────
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? length(var.public_subnet_cidrs) : 0
  domain = "vpc"
  tags   = merge(var.common_tags, { Name = "${var.env_name}-eip-${count.index + 1}" })
}

# ── NAT Gateways (one per AZ) ────────────────────────────────────────────────
resource "aws_nat_gateway" "this" {
  count         = var.enable_nat_gateway ? length(var.public_subnet_cidrs) : 0
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = merge(var.common_tags, { Name = "${var.env_name}-natgw-${count.index + 1}" })
  depends_on    = [aws_internet_gateway.this]
}

# ── Public Route Table ────────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = local.vpc_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = local.igw_id
  }
  tags = merge(var.common_tags, { Name = "${var.env_name}-rt-public" })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Private Route Tables (one per AZ) ────────────────────────────────────────
resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = local.vpc_id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.this[count.index].id
    }
  }

  tags = merge(var.common_tags, { Name = "${var.env_name}-rt-private-${count.index + 1}" })
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ── VPC Flow Logs ─────────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/${var.env_name}-flow-logs"
  retention_in_days = 30
  tags              = var.common_tags
}

resource "aws_iam_role" "flow_log" {
  name = "${var.env_name}-flow-log-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.common_tags
}

resource "aws_iam_role_policy" "flow_log" {
  name = "${var.env_name}-flow-log-policy"
  role = aws_iam_role.flow_log.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "this" {
  vpc_id          = local.vpc_id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  tags            = merge(var.common_tags, { Name = "${var.env_name}-flow-log" })
}
