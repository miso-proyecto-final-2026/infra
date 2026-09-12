# ElastiCache Redis: cache.t3.micro, 1 réplica (perfil de costo mínimo para
# experimentos que se apagan al terminar).

resource "aws_security_group" "redis" {
  name_prefix = "solventa-redis-"
  description = "Acceso a ElastiCache Redis desde los nodos EKS"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_security_group_rule" "redis_ingress_from_eks" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis.id
  source_security_group_id = var.eks_node_security_group_id
}

resource "aws_security_group_rule" "redis_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.redis.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_elasticache_subnet_group" "solventa" {
  name       = "solventa-staging-redis"
  subnet_ids = var.private_subnet_ids
  tags       = var.tags
}

resource "aws_elasticache_replication_group" "solventa" {
  replication_group_id = "solventa-staging-redis"
  description           = "Redis cache-aside para MS Cotizacion y MS Perfilamiento"

  node_type            = "cache.t3.micro"
  engine                = "redis"
  engine_version        = "7.1"
  num_cache_clusters    = 1 # 1 réplica (sin failover multi-AZ, staging)
  port                  = 6379

  subnet_group_name   = aws_elasticache_subnet_group.solventa.name
  security_group_ids  = [aws_security_group.redis.id]

  automatic_failover_enabled = false
  multi_az_enabled           = false

  apply_immediately = true

  tags = var.tags
}
