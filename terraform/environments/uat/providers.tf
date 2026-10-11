terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws    = { source = "hashicorp/aws";    version = "~> 5.0" }
    random = { source = "hashicorp/random"; version = "~> 3.5" }
  }
  # Uncomment after bootstrap:
  # backend "s3" {
  #   bucket         = "496251222247-terraform-state"
  #   key            = "uat/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = "ap-south-1"
  default_tags {
    tags = {
      ManagedBy  = "terraform"
      Repository = "observability-platform"
    }
  }
}
