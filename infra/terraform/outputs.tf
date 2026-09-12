output "namespace" {
  value = kubernetes_namespace.solventa_staging.metadata[0].name
}

output "redis_primary_endpoint" {
  value = aws_elasticache_replication_group.solventa.primary_endpoint_address
}

output "rds_endpoint" {
  value = aws_db_instance.solventa.endpoint
}

output "database_url" {
  value     = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.solventa.endpoint}/${var.db_name}"
  sensitive = true
}

output "redis_url" {
  value = "redis://${aws_elasticache_replication_group.solventa.primary_endpoint_address}:6379/0"
}
