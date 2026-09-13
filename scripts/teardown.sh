#!/usr/bin/env bash
# Apaga TODA la infraestructura (control de créditos AWS): destruye lo
# aprovisionado por Terraform (VPC, EKS, node group, ECR, ElastiCache, RDS,
# namespace). Al destruir el cluster EKS se eliminan automáticamente todos
# los workloads desplegados dentro (Deployments, Services, HPA, etc.), así
# que no hace falta borrar los manifiestos de Kubernetes por separado.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

log "== Terraform destroy (VPC, EKS, ECR, ElastiCache, RDS) =="
pushd infra/terraform > /dev/null
terraform destroy -auto-approve -input=false
popd > /dev/null

log "Teardown completo."
