locals {
  cluster_name = "${var.project_name}-${var.environment}-eks"
}

# Cluster EKS + node group administrado. Tamaño mínimo pensado para correr
# mock-open-finance + ms-cotizacion + ms-perfilamiento (con HPA hasta 10
# réplicas bajo HA02) + observabilidad, en experimentos de corta duración.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.cluster_name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size
    }
  }

  tags = var.tags
}

# kube-metrics-server: requisito explícito del HPA de ms-perfilamiento.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.2"

  depends_on = [module.eks]
}
