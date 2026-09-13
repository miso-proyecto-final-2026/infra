variable "aws_region" {
  description = "Región AWS donde se crea toda la infraestructura"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo usado para nombrar todos los recursos"
  type        = string
  default     = "solventa"
}

variable "environment" {
  description = "Nombre del ambiente (staging, dado que es infra de experimentos)"
  type        = string
  default     = "staging"
}

variable "namespace" {
  description = "Namespace de Kubernetes para los experimentos"
  type        = string
  default     = "solventa-staging"
}

# --- Red ---

variable "vpc_cidr" {
  description = "CIDR block de la VPC creada para el cluster"
  type        = string
  default     = "10.60.0.0/16"
}

variable "az_count" {
  description = "Número de availability zones a usar (2 es suficiente y más barato para experimentos)"
  type        = number
  default     = 2
}

# --- EKS ---

variable "kubernetes_version" {
  description = <<-EOT
    Versión de Kubernetes para el cluster EKS. Dejar en null (default) para
    que EKS use su versión por defecto vigente al momento del apply — evita
    fallos como "Requested AMI for this version X.Y is not supported" cuando
    una versión fijada envejece y AWS deja de construir AMIs para ella.
    Fijar un valor (p.ej. "1.31") solo si necesitas una versión específica;
    verifica antes cuáles soporta tu región con:
    `aws eks describe-addon-versions --query 'addons[0].addonVersions[0].compatibilities[].clusterVersion' --output text`
    o revisando la consola de EKS al crear un cluster manualmente.
  EOT
  type        = string
  default     = null
}

variable "node_instance_type" {
  description = "Tipo de instancia EC2 para el node group de EKS"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 2
}

# --- Base de datos ---

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
