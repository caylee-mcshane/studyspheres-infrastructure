variable "environment" {
  description = "The environment name"
  type        = string
  default     = "staging"
}

variable "db_password" {
  description = "RDS Root Password"
  type        = string
  sensitive   = true
}

variable "db_app_password" {
  description = "Password for the studyspheres_app non-owner role (SSM PG_APP_PASSWORD)"
  type        = string
  sensitive   = true
}

variable "cognito_pool_id" {
  type    = string
  default = "us-east-1_zYyPI7xxr"
}

variable "cognito_client_id" {
  type    = string
  default = "5fh6oeet0a8tm4soth3hhpfcn7"
}

variable "cognito_domain" {
  type    = string
  default = "us-east-1zyypi7xxr.auth.us-east-1.amazoncognito.com"
}