terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.6"
    }
  }

  # For a team setup, keep state in S3 with locking, e.g.:
  # backend "s3" {
  #   bucket       = "my-tf-state"
  #   key          = "fdic-bank-health/terraform.tfstate"
  #   region       = "us-east-1"
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project     = "fdic-bank-health"
      environment = var.environment
      managed_by  = "terraform"
    }
  }
}
