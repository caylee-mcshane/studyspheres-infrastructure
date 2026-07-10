variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "instance_type" {
  type = string
}

variable "min_size" {
  type = number
}

variable "max_size" {
  type = number
}

variable "db_endpoint" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "cognito_pool_id" {
  type = string
}

variable "cognito_client_id" {
  type = string
}

variable "cognito_domain" {
  type = string
}