terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.55.0"
    }
  }

  backend "s3" {
    encrypt        = true
  }
}

provider "aws" {
  region = "us-west-2"
}
