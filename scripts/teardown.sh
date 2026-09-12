#!/usr/bin/env bash
# Apaga toda la infraestructura del namespace de staging (control de
# créditos AWS): elimina manifiestos k8s y destruye lo aprovisionado por
# Terraform (ElastiCache, RDS, namespace).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

log "== Eliminando manifiestos de Kubernetes =="
kubectl delete -f observability/otel-collector-k8s.yaml --ignore-not-found
kubectl delete -f ms-perfilamiento/k8s/ --ignore-not-found
kubectl delete -f ms-cotizacion/k8s/ --ignore-not-found
kubectl delete -f mock-open-finance/k8s/ --ignore-not-found

log "== Terraform destroy =="
pushd infra/terraform > /dev/null
terraform destroy -auto-approve -input=false
popd > /dev/null

log "Teardown completo."
