provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

# El cluster EKS lo crea este mismo módulo (ver eks.tf); los providers de
# kubernetes y helm se autentican contra él usando sus outputs, más un token
# de corta duración vía el data source de autenticación de EKS (evita
# depender de un exec/aws-iam-authenticator externo).
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}
