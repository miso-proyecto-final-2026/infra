#!/usr/bin/env bash
# Levanta TODA la infraestructura (VPC, EKS, node group, ECR, ElastiCache,
# RDS, namespace y metrics-server vía Terraform) y despliega los manifiestos
# de Kubernetes. Pensado para levantarse bajo demanda y apagarse con
# teardown.sh al terminar (control de créditos AWS).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

command -v terraform > /dev/null 2>&1 || { err "terraform no está instalado."; exit 1; }
command -v aws > /dev/null 2>&1 || { err "aws CLI no está instalado."; exit 1; }
command -v kubectl > /dev/null 2>&1 || { err "kubectl no está instalado."; exit 1; }
command -v envsubst > /dev/null 2>&1 || { err "envsubst no está instalado (paquete gettext-base)."; exit 1; }

log "== Terraform: aprovisionando VPC, EKS, ECR, ElastiCache y RDS =="
log "(esto tarda ~15-20 min, principalmente por la creación del cluster EKS)"
pushd infra/terraform > /dev/null
terraform init -input=false
terraform apply -auto-approve -input=false

CLUSTER_NAME=$(terraform output -raw cluster_name)
AWS_REGION=$(terraform output -raw aws_region)
ECR_URLS_JSON=$(terraform output -json ecr_repository_urls)
DATABASE_URL=$(terraform output -raw database_url)
export REDIS_ENDPOINT
REDIS_ENDPOINT=$(terraform output -raw redis_primary_endpoint)
popd > /dev/null

log "== Apuntando kubectl al cluster ${CLUSTER_NAME} =="
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

log "== Build & push de imágenes a ECR =="
./scripts/build-and-push.sh

export MOCK_OPEN_FINANCE_IMAGE="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['mock-open-finance'])" "${ECR_URLS_JSON}"):latest"
export MS_COTIZACION_IMAGE="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['ms-cotizacion'])" "${ECR_URLS_JSON}"):latest"
export MS_PERFILAMIENTO_IMAGE="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['ms-perfilamiento'])" "${ECR_URLS_JSON}"):latest"

log "== Creando secret de base de datos =="
kubectl create secret generic solventa-db-secret -n "${NAMESPACE}" \
  --from-literal=DATABASE_URL="${DATABASE_URL}" \
  --dry-run=client -o yaml | kubectl apply -f -

log "== Aplicando manifiestos de Kubernetes =="
envsubst < mock-open-finance/k8s/deployment.yaml | kubectl apply -f -
kubectl apply -f mock-open-finance/k8s/service.yaml

envsubst < ms-cotizacion/k8s/deployment.yaml | kubectl apply -f -
kubectl apply -f ms-cotizacion/k8s/service.yaml

envsubst < ms-perfilamiento/k8s/deployment.yaml | kubectl apply -f -
kubectl apply -f ms-perfilamiento/k8s/service.yaml
kubectl apply -f ms-perfilamiento/k8s/hpa.yaml

kubectl apply -f observability/otel-collector-k8s.yaml

wait_for_pods_running 300

log "== Esperando LoadBalancers públicos (AWS suele tardar 2-5 min) =="
MOCK_URL=$(wait_for_loadbalancer mock-open-finance)
COTIZACION_URL=$(wait_for_loadbalancer ms-cotizacion)
PERFILAMIENTO_URL=$(wait_for_loadbalancer ms-perfilamiento)

log "Setup completo. Namespace: ${NAMESPACE}. Cluster: ${CLUSTER_NAME}"
log ""
log "Exporta esto antes de correr run-exp1.sh / run-exp2.sh:"
log "  export MOCK_URL=${MOCK_URL}"
log "  export COTIZACION_URL=${COTIZACION_URL}"
log "  export PERFILAMIENTO_URL=${PERFILAMIENTO_URL}"
log "(run-exp1.sh y run-exp2.sh también las descubren solas si no las exportas)"
