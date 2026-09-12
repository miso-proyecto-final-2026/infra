variable "aws_region" {
  description = "Región AWS donde vive el cluster EKS y los recursos de datos"
  type        = string
  default     = "us-east-1"
}

variable "eks_cluster_name" {
  description = "Nombre del cluster EKS existente donde correr los experimentos"
  type        = string
}

variable "vpc_id" {
  description = "VPC donde viven el EKS y la infraestructura de datos"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas para ElastiCache y RDS"
  type        = list(string)
}

variable "eks_node_security_group_id" {
  description = "Security group de los nodos EKS, para autorizar acceso a Redis/RDS"
  type        = string
}

variable "namespace" {
  description = "Namespace de Kubernetes para los experimentos"
  type        = string
  default     = "solventa-staging"
}

variable "db_name" {
  type    = string
  default = "solventa"
}

variable "db_username" {
  type    = string
  default = "solventa"
}

variable "db_password" {
  description = "Password de RDS. Pasar vía TF_VAR_db_password o un secret manager, nunca commitear."
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags comunes aplicados a todos los recursos"
  type        = map(string)
  default = {
    Project     = "solventa-experimentos"
    Environment = "staging"
    ManagedBy   = "terraform"
  }
}
