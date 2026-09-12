#!/usr/bin/env bash
# Funciones compartidas entre los scripts de scripts/.
set -euo pipefail

NAMESPACE="${NAMESPACE:-solventa-staging}"
RESULTS_DIR="${RESULTS_DIR:-results}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

wait_for_pods_running() {
  log "Verificando que todos los pods de ${NAMESPACE} estén Running..."
  local timeout_s="${1:-180}"
  local elapsed=0
  while true; do
    local not_ready
    not_ready=$(kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null \
      | awk '{split($2,a,"/"); if (a[1]!=a[2] || $3!="Running") print $0}')
    if [ -z "${not_ready}" ]; then
      log "Todos los pods están Running."
      return 0
    fi
    if [ "${elapsed}" -ge "${timeout_s}" ]; then
      echo "Timeout esperando pods Running en ${NAMESPACE}:" >&2
      echo "${not_ready}" >&2
      exit 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

flush_redis() {
  log "Limpiando caché Redis (FLUSHALL)..."
  kubectl exec -n "${NAMESPACE}" deploy/redis -- redis-cli FLUSHALL \
    || redis-cli -u "${REDIS_URL:-redis://localhost:6379/0}" FLUSHALL
}

set_mock_latency() {
  local min_ms="$1"
  local max_ms="$2"
  log "Configurando mock Open Finance: min_ms=${min_ms} max_ms=${max_ms}"
  curl -sf -X PUT "${MOCK_URL:-http://localhost:8000}/config/latency" \
    -H 'Content-Type: application/json' \
    -d "{\"min_ms\": ${min_ms}, \"max_ms\": ${max_ms}}" > /dev/null
}

ensure_results_dir() {
  mkdir -p "${RESULTS_DIR}"
}
