terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>5.35.0"
    }
  }
  required_version = "~>1.6.0"
  backend "s3" {
    bucket         = "terraform-bucketja"
    key            = "EC2_ONDEMAND_JA/terraform.tfstate"
    dynamodb_table = "terraform-table"
    region         = "us-east-1"
  }
}
#s
provider "aws" {
  # Configuration options
  region = var.region
}