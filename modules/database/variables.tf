variable "environment" {
  description = "The environment name (e.g., staging, production)"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "The CIDR block of the VPC to allow internal traffic"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the database"
  type        = list(string)
}

variable "instance_class" {
  description = "The RDS instance size"
  type        = string
}

variable "multi_az" {
  description = "Whether to deploy across multiple Availability Zones"
  type        = bool
}