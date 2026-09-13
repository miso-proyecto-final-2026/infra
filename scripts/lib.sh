#!/usr/bin/env bash
# Funciones compartidas entre los scripts de scripts/.
set -euo pipefail

NAMESPACE="${NAMESPACE:-solventa-staging}"
RESULTS_DIR="${RESULTS_DIR:-results}"
# Poner en "true" para correr contra docker-compose local en lugar de un
# cluster de Kubernetes: omite la verificación de pods y usa redis-cli
# directo en flush_redis.
SKIP_K8S_CHECK="${SKIP_K8S_CHECK:-false}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

err() {
  echo "ERROR: $*" >&2
}

wait_for_pods_running() {
  if [ "${SKIP_K8S_CHECK}" = "true" ]; then
    log "SKIP_K8S_CHECK=true: omitiendo verificación de pods (modo local / docker-compose)."
    return 0
  fi

  log "Verificando que todos los pods de ${NAMESPACE} estén Running..."

  if ! kubectl cluster-info > /dev/null 2>&1; then
    err "kubectl no pudo contactar ningún cluster (¿contexto no configurado con 'kubectl config use-context'?)."
    err "Si estás corriendo localmente contra docker-compose, exporta SKIP_K8S_CHECK=true."
    exit 1
  fi

  local timeout_s="${1:-180}"
  local elapsed=0
  while true; do
    local not_ready
    if ! not_ready=$(kubectl get pods -n "${NAMESPACE}" --no-headers 2>&1); then
      err "kubectl get pods -n ${NAMESPACE} falló:"
      err "${not_ready}"
      exit 1
    fi
    not_ready=$(echo "${not_ready}" \
      | awk '{split($2,a,"/"); if (a[1]!=a[2] || $3!="Running") print $0}')
    if [ -z "${not_ready}" ]; then
      log "Todos los pods están Running."
      return 0
    fi
    if [ "${elapsed}" -ge "${timeout_s}" ]; then
      err "Timeout esperando pods Running en ${NAMESPACE}:"
      err "${not_ready}"
      exit 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

flush_redis() {
  local redis_url="${REDIS_URL:?flush_redis requiere REDIS_URL definida (ver resolve_redis_url)}"
  log "Limpiando caché Redis (FLUSHALL) en ${redis_url}..."

  if [ "${SKIP_K8S_CHECK}" = "true" ]; then
    if command -v redis-cli > /dev/null 2>&1; then
      if ! redis-cli -u "${redis_url}" FLUSHALL; then
        err "No se pudo conectar a Redis en ${redis_url}."
        err "¿Está corriendo 'docker compose up'?"
        exit 1
      fi
    elif docker compose ps redis > /dev/null 2>&1; then
      # redis-cli no está instalado en el host: usar el binario dentro del
      # contenedor levantado por docker-compose.
      if ! docker compose exec -T redis redis-cli FLUSHALL; then
        err "No se pudo hacer FLUSHALL vía 'docker compose exec redis'."
        exit 1
      fi
    else
      err "redis-cli no está instalado y no hay contenedor 'redis' de docker-compose corriendo."
      err "Instala redis-tools (apt install redis-tools) o levanta el stack con 'docker compose up'."
      exit 1
    fi
    return 0
  fi

  # En AWS, Redis es ElastiCache: un endpoint gestionado en una subnet
  # privada, no un Service de k8s. Se usa un pod efímero dentro del cluster
  # (misma VPC) para poder alcanzarlo y ejecutar el FLUSHALL.
  if ! kubectl run "redis-flush-$(date +%s)" --rm -i --restart=Never \
    --image=redis:7.2-alpine -n "${NAMESPACE}" --command \
    -- redis-cli -u "${redis_url}" FLUSHALL; then
    err "No se pudo hacer FLUSHALL contra ${redis_url} vía pod efímero en ${NAMESPACE}."
    exit 1
  fi
}

# Resuelve REDIS_URL: usa la variable de entorno si ya está exportada, si no
# la lee de `terraform output redis_primary_endpoint` (modo AWS) o usa el
# default de docker-compose (modo local).
resolve_redis_url() {
  local db_index="${1:-0}"
  if [ -n "${REDIS_URL:-}" ]; then
    echo "${REDIS_URL}"
    return 0
  fi
  if [ "${SKIP_K8S_CHECK}" = "true" ]; then
    echo "redis://localhost:6379/${db_index}"
    return 0
  fi
  local endpoint
  endpoint=$(cd infra/terraform && terraform output -raw redis_primary_endpoint 2>/dev/null) || true
  if [ -z "${endpoint}" ]; then
    err "No se pudo leer redis_primary_endpoint de 'terraform output' y REDIS_URL no está definida."
    err "Exporta REDIS_URL manualmente (ver 'terraform output redis_primary_endpoint' en infra/terraform)."
    exit 1
  fi
  echo "redis://${endpoint}:6379/${db_index}"
}

set_mock_latency() {
  local min_ms="$1"
  local max_ms="$2"
  log "Configurando mock Open Finance: min_ms=${min_ms} max_ms=${max_ms}"
  local response
  if ! response=$(curl -sf -X PUT "${MOCK_URL:-http://localhost:8000}/config/latency" \
    -H 'Content-Type: application/json' \
    -d "{\"min_ms\": ${min_ms}, \"max_ms\": ${max_ms}}" 2>&1); then
    err "No se pudo configurar la latencia del mock en ${MOCK_URL:-http://localhost:8000}."
    err "¿Está corriendo el servicio? Detalle: ${response}"
    exit 1
  fi
}

ensure_results_dir() {
  mkdir -p "${RESULTS_DIR}"
}

# Devuelve el hostname/IP público del Service tipo LoadBalancer dado, o
# cadena vacía si aún no fue asignado por AWS.
lb_host() {
  local svc="$1"
  local host
  host=$(kubectl get svc "${svc}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [ -z "${host}" ]; then
    host=$(kubectl get svc "${svc}" -n "${NAMESPACE}" \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  fi
  echo "${host}"
}

# Espera hasta que el Service tenga un LoadBalancer asignado (AWS suele
# tardar 2-4 min en NLB, más en Classic ELB) e imprime su URL http://.
wait_for_loadbalancer() {
  local svc="$1"
  local timeout_s="${2:-300}"
  local elapsed=0
  log "Esperando hostname/IP del LoadBalancer de '${svc}'..." >&2
  while true; do
    local host
    host=$(lb_host "${svc}")
    if [ -n "${host}" ]; then
      log "'${svc}' disponible en: http://${host}:8000" >&2
      echo "http://${host}:8000"
      return 0
    fi
    if [ "${elapsed}" -ge "${timeout_s}" ]; then
      err "Timeout esperando el LoadBalancer de '${svc}'."
      err "Revisa 'kubectl get svc ${svc} -n ${NAMESPACE}' y 'kubectl describe svc ${svc} -n ${NAMESPACE}'."
      exit 1
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
}

# Resuelve una URL de servicio: usa la variable de entorno si ya está
# exportada, si no la descubre vía el LoadBalancer de Kubernetes (modo AWS)
# o cae al default de docker-compose (modo local, si se pasa uno).
resolve_service_url() {
  local var_name="$1"
  local svc_name="$2"
  local local_default="${3:-}"
  local current="${!var_name:-}"
  if [ -n "${current}" ]; then
    echo "${current}"
    return 0
  fi
  if [ "${SKIP_K8S_CHECK}" = "true" ]; then
    if [ -n "${local_default}" ]; then
      echo "${local_default}"
      return 0
    fi
    err "${var_name} no está definida. En modo local (SKIP_K8S_CHECK=true) debes exportarla, p.ej.:"
    err "  export ${var_name}=http://localhost:8000"
    exit 1
  fi
  wait_for_loadbalancer "${svc_name}"
}
