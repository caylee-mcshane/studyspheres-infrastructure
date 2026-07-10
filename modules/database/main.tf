# 1. Group our private subnets together for RDS
resource "aws_db_subnet_group" "main" {
  name       = "studyspheres-${var.environment}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "studyspheres-${var.environment}-db-subnet-group"
  }
}

# 2. Security Group (Firewall) - Only allow traffic from inside the VPC
resource "aws_security_group" "rds_sg" {
  name        = "studyspheres-${var.environment}-rds-sg"
  description = "Allow inbound PostgreSQL traffic from the VPC"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. Generate a secure random password
resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# 4. The actual PostgreSQL Database
resource "aws_db_instance" "postgres" {
  identifier           = "studyspheres-${var.environment}-db"
  engine               = "postgres"
  engine_version       = "16.3" # Supports pgvector
  instance_class       = var.instance_class
  allocated_storage    = 20
  storage_type         = "gp3"
  
  db_name              = "studyspheres"
  username             = "postgres"
  password             = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  
  multi_az               = var.multi_az
  publicly_accessible    = false
  skip_final_snapshot    = true # Set to false in a real production environment later
}