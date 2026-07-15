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

# The Postgres role the app connects as. Default keeps environments on the
# RDS master user until they opt in to the dedicated non-owner app role
# (RLS enforcement, ADR-0004 Option B). Staging opts in; production must
# not until the role + PG_APP_PASSWORD param exist on its database.
variable "db_app_user" {
  type    = string
  default = "postgres"
}

# Password for the non-owner app role, stored as PG_APP_PASSWORD in SSM.
# Empty (the default) skips creating the SSM param — required while an
# environment still connects as the master user.
variable "db_app_password" {
  type      = string
  sensitive = true
  default   = ""
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