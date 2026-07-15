terraform {
  backend "s3" {
    bucket         = "studyspheres-terraform-state-2026"
    # Notice this state file is safely isolated in a /production path
    key            = "production/terraform.tfstate"
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
      Environment = "production"
      Project     = "studyspheres"
      ManagedBy   = "terraform"
    }
  }
}

# 1. Build the Production Network
module "networking" {
  source = "../../modules/networking"

  environment          = "production"
  
  # We use the 10.1.x.x block for Prod so it never overlaps with Staging (10.0.x.x)
  vpc_cidr             = "10.1.0.0/16"
  public_subnets_cidr  = ["10.1.1.0/24", "10.1.2.0/24"]
  private_subnets_cidr = ["10.1.10.0/24", "10.1.11.0/24"]
}

# 2. Build the Production Database
module "database" {
  source = "../../modules/database"

  environment          = "production"
  vpc_id               = module.networking.vpc_id
  vpc_cidr             = "10.1.0.0/16"
  private_subnet_ids   = module.networking.private_subnet_ids
  
  # Production Reliability: Larger instance, Multi-AZ for failover
  instance_class       = "db.t3.small"
  multi_az             = true
}

# 3. Build the Production Compute Tier
module "compute" {
  source = "../../modules/compute"

  environment        = "production"
  vpc_id             = module.networking.vpc_id
  public_subnet_ids  = module.networking.public_subnet_ids
  private_subnet_ids = module.networking.private_subnet_ids
  db_endpoint        = module.database.db_endpoint
  db_password        = module.database.db_password

  # Cognito identifiers (public, not secrets). Currently the same single
  # user pool as staging (us-east-1_zYyPI7xxr) — see architecture docs. These
  # became required module args in 4022136; production's call had not been
  # updated, so `terraform validate`/`plan` failed here. Hygiene fix only —
  # production remains undeployed (no app, no S3 buckets, most SSM secrets
  # absent); see the prod-launch checklist before any prod apply.
  #
  # NOTE: db_app_user is intentionally left at its module default (postgres).
  # Option B (studyspheres_app role) is folded into the future prod launch,
  # baked in from day one at that point — not applied to this dead instance.
  cognito_pool_id    = "us-east-1_zYyPI7xxr"
  cognito_client_id  = "5fh6oeet0a8tm4soth3hhpfcn7"
  cognito_domain     = "us-east-1zyypi7xxr.auth.us-east-1.amazoncognito.com"

  # Production Auto-Scaling constraints
  instance_type      = "t3.small"
  min_size           = 1  # Standard load
  max_size           = 3  # Maximum scale-out during usage spikes
}