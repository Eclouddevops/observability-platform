###############################################################################
# Bootstrap — Remote State Backend
# Run ONCE before any environment to create the S3 bucket + DynamoDB table
# used for Terraform state locking.
#
# Usage:
#   cd terraform/bootstrap
#   terraform init && terraform apply
###############################################################################

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

locals {
  account_id = "496251222247"
  bucket_name = "${local.account_id}-terraform-state"
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  tags = {
    Name      = "terraform-remote-state"
    ManagedBy = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "lock" {
  name         = "terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name      = "terraform-state-lock"
    ManagedBy = "terraform"
  }
}

output "state_bucket_name" {
  value = aws_s3_bucket.state.bucket
}

output "dynamodb_lock_table" {
  value = aws_dynamodb_table.lock.name
}
