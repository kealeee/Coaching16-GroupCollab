provider "aws" {
  region = var.AWS_REGION
}

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.66.0"
    }
  }

  backend "s3" {
    bucket = "sctp-tfstate-ce13"
    key    = "group-4/tfstate/coaching-16"
    region = "us-east-1"
  }
}