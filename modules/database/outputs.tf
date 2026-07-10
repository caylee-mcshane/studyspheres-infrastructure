output "db_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "db_password" {
  value     = aws_db_instance.postgres.password
  sensitive = true
}