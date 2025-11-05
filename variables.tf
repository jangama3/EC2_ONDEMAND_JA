terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    local   = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
  }
}

variable "region" {
  description = "AWS region to deploy"
  type        = string
  default     = "us-east-1"
}

variable "tag_key" {
  description = "Tag key to filter EC2 instances"
  type        = string
  default     = "Environment"
}

variable "tag_value" {
  description = "Tag value to filter EC2 instances"
  type        = string
  default     = "Dev"
}

variable "lambda_name" {
  description = "Name for the Lambda function"
  type        = string
  default     = "ec2-control-lambda"
}
