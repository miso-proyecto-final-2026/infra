# RDS PostgreSQL: db.t3.micro, staging, Multi-AZ deshabilitado.

resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-rds-"
  description = "Acceso a RDS PostgreSQL desde los nodos EKS"
  vpc_id      = module.vpc.vpc_id
  tags        = var.tags
}

resource "aws_security_group_rule" "rds_ingress_from_eks" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = module.eks.node_security_group_id
}

resource "aws_security_group_rule" "rds_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.rds.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_db_subnet_group" "solventa" {
  name       = "${var.project_name}-${var.environment}-db"
  subnet_ids = module.vpc.private_subnets
  tags       = var.tags
}

resource "aws_db_instance" "solventa" {
  identifier     = "${var.project_name}-${var.environment}-pg"
  engine         = "postgres"
  engine_version = "16.4"

  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.solventa.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = false
  publicly_accessible = false

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  tags = var.tags
}
