# Bootstrap: creates S3 bucket + DynamoDB table for remote Terraform state
# Run ONCE with local state before initializing staging env:
#   cd terraform/envs/bootstrap
#   terraform init
#   terraform apply -var bucket_name="max-weather-tfstate-$(aws sts get-caller-identity --query Account --output text)"
# After apply: update terraform/envs/staging/backend.tf with bucket name + key

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

module "bootstrap" {
  source              = "../../modules/bootstrap"
  bucket_name         = var.bucket_name
  dynamodb_table_name = var.dynamodb_table_name
  region              = var.region
  tags                = var.tags
}

variable "bucket_name" {
  description = "S3 bucket name for Terraform state (must be globally unique)"
  type        = string
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "max-weather-tflock"
}

variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "tags" {
  type    = map(string)
  default = { Project = "max-weather", ManagedBy = "terraform" }
}

output "bucket_name" { value = module.bootstrap.bucket_name }
output "dynamodb_table_name" { value = module.bootstrap.dynamodb_table_name }
