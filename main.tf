terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket       = "mohammed-terraform-state-2026" # must match state_bucket_name above
    key          = "vpc-project/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
    #  profile      = "midoprofile"
  }

}

provider "aws" {
  region = var.aws_region
  # profile = var.aws_profile
}

provider "aws" {
  alias   = "dr_region"
  region  = var.aws_dr_region
  # profile = var.aws_profile
}

