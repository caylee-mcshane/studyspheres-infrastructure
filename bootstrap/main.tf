terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Tell Terraform to use the IAM user you configured earlier
provider "aws" {
  region  = "us-east-1"
  profile = "terraform"
}

# 1. Create the S3 Bucket for the State File
resource "aws_s3_bucket" "terraform_state" {
  bucket = "studyspheres-terraform-state-2026"
  
  # Prevent accidental deletion of this critical S3 bucket
  lifecycle {
    prevent_destroy = true
  }
}

# Enable versioning so you can roll back if the state file gets corrupted
resource "aws_s3_bucket_versioning" "enabled" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Block all public access to the state file (it contains sensitive info)
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# 2. Create the DynamoDB Table for State Locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "studyspheres-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# Output the names so we can copy-paste them later
output "s3_bucket_name" {
  value = aws_s3_bucket.terraform_state.bucket
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.terraform_locks.name
}