# VPC dedicada para los experimentos: 2 AZs, subnets públicas (para el NAT
# y, si se necesita, un LoadBalancer) y privadas (EKS, ElastiCache, RDS).
# Un solo NAT gateway para minimizar costo mientras la infra esté arriba.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${var.project_name}-${var.environment}-vpc"
  cidr = var.vpc_cidr

  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + var.az_count)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  tags = var.tags
}
