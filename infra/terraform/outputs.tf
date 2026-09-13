output "cluster_name" {
  value = module.eks.cluster_name
}

output "aws_region" {
  value = var.aws_region
}

output "configure_kubectl" {
  description = "Comando para apuntar kubectl al cluster recién creado"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "namespace" {
  value = kubernetes_namespace.solventa_staging.metadata[0].name
}

output "ecr_repository_urls" {
  description = "URL de cada repositorio ECR, para build/push (ver scripts/build-and-push.sh)"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
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
