variable "environment" {
  description = "The deployment environment (e.g., staging, prod)"
  type        = string
}

variable "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer for API routing"
  type        = string
}