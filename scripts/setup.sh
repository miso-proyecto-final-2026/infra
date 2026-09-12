#!/usr/bin/env bash
# Levanta la infraestructura del namespace de staging: terraform apply +
# despliegue de manifiestos k8s. Pensado para levantarse bajo demanda y
# apagarse con teardown.sh al terminar (control de créditos AWS).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

log "== Terraform: aprovisionando namespace, ElastiCache y RDS =="
pushd infra/terraform > /dev/null
terraform init -input=false
terraform apply -auto-approve -input=false
popd > /dev/null

log "== Aplicando manifiestos de Kubernetes =="
kubectl apply -f mock-open-finance/k8s/
kubectl apply -f ms-cotizacion/k8s/
kubectl apply -f ms-perfilamiento/k8s/
kubectl apply -f observability/otel-collector-k8s.yaml

wait_for_pods_running 300

log "Setup completo. Namespace: ${NAMESPACE}"
