###############################################################################
# UAT — Providers
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # ── Remote State ──────────────────────────────────────────────────────────
  # Uncomment and configure before first apply.
  # backend "s3" {
  #   bucket         = "496251222247-terraform-state"
  #   key            = "uat/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = "uat"
      ManagedBy   = "terraform"
      Repository  = "observability-platform"
    }
  }
}
