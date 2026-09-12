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
  log "Limpiando caché Redis (FLUSHALL)..."
  if [ "${SKIP_K8S_CHECK}" = "true" ]; then
    if command -v redis-cli > /dev/null 2>&1; then
      if ! redis-cli -u "${REDIS_URL:-redis://localhost:6379/0}" FLUSHALL; then
        err "No se pudo conectar a Redis en ${REDIS_URL:-redis://localhost:6379/0}."
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
  if ! kubectl exec -n "${NAMESPACE}" deploy/redis -- redis-cli FLUSHALL; then
    err "No se pudo hacer FLUSHALL vía kubectl exec en ${NAMESPACE}."
    exit 1
  fi
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
