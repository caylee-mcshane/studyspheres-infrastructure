module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "studyspheres-${var.environment}-vpc"
  cidr = var.vpc_cidr

  # Spread across 2 Availability Zones for High Availability
  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = var.private_subnets_cidr
  public_subnets  = var.public_subnets_cidr

  enable_nat_gateway = true
  # COST OPTIMIZATION: Use 1 NAT Gateway instead of 1 per AZ to save ~$32/month
  single_nat_gateway = true 

  enable_dns_hostnames = true
  enable_dns_support   = true
}

# COST OPTIMIZATION: S3 Gateway Endpoint
# Keeps PDF/Audio uploads on the internal AWS network, avoiding NAT data processing charges.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids
}

# COST OPTIMIZATION: DynamoDB Gateway Endpoint
# Keeps fast-paced DB queries on the internal network.
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.us-east-1.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids
}