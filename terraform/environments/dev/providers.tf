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
