terraform {
  backend "s3" {
    bucket         = "studyspheres-terraform-state-2026"
    key            = "staging/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "studyspheres-terraform-locks"
    encrypt        = true
    profile        = "terraform"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "terraform"
  
  default_tags {
    tags = {
      Environment = "staging"
      Project     = "studyspheres"
      ManagedBy   = "terraform"
    }
  }
}

# 1. Build the Staging Network
module "networking" {
  source = "../../modules/networking"

  environment          = "staging"
  vpc_cidr             = "10.0.0.0/16"
  public_subnets_cidr  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets_cidr = ["10.0.10.0/24", "10.0.11.0/24"]
}

# 2. Build the Staging Database
module "database" {
  source = "../../modules/database"

  environment          = "staging"
  vpc_id               = module.networking.vpc_id
  vpc_cidr             = "10.0.0.0/16"
  private_subnet_ids   = module.networking.private_subnet_ids
  
  # Cost Optimization: Small, Single-AZ instance for Staging
  instance_class       = "db.t3.micro"
  multi_az             = false
}

# 3. Build the Staging Compute Tier
module "compute" {
  source = "../../modules/compute"

  environment        = var.environment
  vpc_id             = module.networking.vpc_id
  public_subnet_ids  = module.networking.public_subnet_ids
  private_subnet_ids = module.networking.private_subnet_ids
  db_endpoint        = module.database.db_endpoint
  db_password        = var.db_password

  cognito_pool_id    = var.cognito_pool_id
  cognito_client_id  = var.cognito_client_id
  cognito_domain     = var.cognito_domain

  instance_type      = "t3.small"
  min_size           = 1
  max_size           = 1
}

# 4. Build the Staging Storage & CDN
module "storage" {
  source       = "../../modules/storage"
  environment  = var.environment
  alb_dns_name = module.compute.alb_dns_name
}

# 5. Build the Security & Identity Tier
module "security" {
  source = "../../modules/security"

  environment           = var.environment
  aws_region            = "us-east-1" 
  cognito_user_pool_id  = var.cognito_pool_id     # Pulling from your existing variables!
  cognito_client_id     = var.cognito_client_id   # Pulling from your existing variables!

  user_profiles_table_arn     = module.dynamodb.table_arns["user_profiles"]
  user_tokens_table_arn       = module.dynamodb.table_arns["user_tokens"]
  user_shared_files_table_arn = module.dynamodb.table_arns["user_shared_files"]
  user_data_bucket_arn        = module.storage.user_data_bucket_arn
}

# 6. NoSQL Application Tables (DynamoDB)
module "dynamodb" {
  source = "../../modules/dynamodb"

  environment = var.environment
}

# Add to environments/staging/outputs.tf (create the file if it doesn't exist)
output "cognito_test_client_id" {
  description = "App Client ID for pytest authentication. Use in .env.test."
  value       = module.security.test_client_id
}

output "frontend_test_runner_role_arn" {
  description = "ARN of the IAM role GitHub Actions assumes for frontend tests"
  value       = module.security.frontend_test_runner_role_arn
}

output "github_actions_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider (reusable for other repos)"
  value       = module.security.github_actions_oidc_provider_arn
}