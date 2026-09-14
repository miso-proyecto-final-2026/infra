#!/usr/bin/env bash
# Apaga TODA la infraestructura (control de créditos AWS): destruye lo
# aprovisionado por Terraform (VPC, EKS, node group, ECR, ElastiCache, RDS,
# namespace). Al destruir el cluster EKS se eliminan automáticamente todos
# los workloads desplegados dentro (Deployments, Services, HPA, etc.), así
# que no hace falta borrar los manifiestos de Kubernetes por separado.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

# Los Services de tipo LoadBalancer los crea el cloud provider de Kubernetes,
# NO Terraform: no están en el state y `terraform destroy` no los conoce. Si
# se destruye el cluster con los Services todavía existentes, los balanceadores
# quedan huérfanos (cobrando) y sus interfaces de red siguen adjuntas a las
# subredes, lo que hace que la eliminación de la VPC falle o se cuelgue ~20 min
# hasta rendirse. Borrarlos primero deja que el controlador los elimine
# ordenadamente antes de tocar la infraestructura.
if kubectl cluster-info > /dev/null 2>&1; then
  log "== Eliminando Services LoadBalancer (para que AWS libere los NLB) =="
  kubectl delete svc -n "${NAMESPACE}" --field-selector spec.type!=ClusterIP \
    --ignore-not-found --wait=true --timeout=180s 2>&1 || true

  log "Esperando a que AWS libere los balanceadores..."
  for _ in $(seq 1 30); do
    vivos=$( { aws elbv2 describe-load-balancers --query 'length(LoadBalancers)' --output text 2>/dev/null || echo 0; } )
    clasicos=$( { aws elb describe-load-balancers --query 'length(LoadBalancerDescriptions)' --output text 2>/dev/null || echo 0; } )
    [ "${vivos}" = "0" ] && [ "${clasicos}" = "0" ] && break
    log "  quedan ${vivos} NLB/ALB y ${clasicos} clásicos; esperando 10s..."
    sleep 10
  done
else
  log "kubectl no alcanza el cluster; se omite la limpieza de Services."
fi

log "== Terraform destroy (VPC, EKS, ECR, ElastiCache, RDS) =="
pushd infra/terraform > /dev/null
terraform destroy -auto-approve -input=false
popd > /dev/null

log "Teardown completo."
