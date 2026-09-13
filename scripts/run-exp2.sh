#!/usr/bin/env bash
# HA02 — Throughput de perfilamiento en línea.
#
# 1. Verifica/genera el dataset sintético que consume k6
# 2. Reconfigura mock a latencia base (300ms fijo)
# 3. Limpia Redis
# 4. Arranca el muestreo de HPA/réplicas/CPU en background
# 5. Ejecuta k6 con las 4 fases secuenciales (rampa, meseta, sobrecarga, recuperación)
# 6. Exporta resultados + estado final del HPA y eventos del namespace
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

RUN_ID="$(date '+%Y%m%d-%H%M%S')"
RESULTS_DIR="${RESULTS_DIR}/${RUN_ID}-ha02"
ensure_results_dir
log "Resultados de esta corrida en: ${RESULTS_DIR}/ (no se sobrescriben entre corridas)"

# k6/data/*.json está en .gitignore: en un clon limpio el dataset no existe y
# k6 aborta en el init con "open ./data/profiles_exp2.json: no such file".
if [ ! -f k6/data/profiles_exp2.json ]; then
  log "k6/data/profiles_exp2.json no existe; generando datasets sintéticos..."
  python3 k6/data/generate_data.py
fi

wait_for_pods_running 180

# En AWS se auto-descubren vía el LoadBalancer de cada Service si no se
# exportan explícitamente; en local (SKIP_K8S_CHECK=true) deben exportarse.
PERFILAMIENTO_URL="$(resolve_service_url PERFILAMIENTO_URL ms-perfilamiento http://localhost:8002)"
MOCK_URL="$(resolve_service_url MOCK_URL mock-open-finance http://localhost:8000)"
REDIS_URL="$(resolve_redis_url 1)"

log "== Configurando mock a latencia base (300ms) =="
set_mock_latency 300 300
flush_redis

# Estado de partida, para poder contrastar contra el final.
if [ "${SKIP_K8S_CHECK}" != "true" ]; then
  kubectl describe hpa ms-perfilamiento-hpa -n "${NAMESPACE}" \
    > "${RESULTS_DIR}/hpa-antes.txt" 2>&1 || true
  kubectl get nodes -o wide > "${RESULTS_DIR}/nodes.txt" 2>&1 || true
  kubectl describe nodes | grep -A 8 "Allocated resources" \
    > "${RESULTS_DIR}/nodes-allocated-antes.txt" 2>&1 || true

  log "== Arrancando muestreo de HPA/réplicas/CPU cada 15s =="
  ./scripts/sample-cluster.sh "${RESULTS_DIR}/cluster-samples.csv" 15 &
  SAMPLER_PID=$!
  # Asegura que el muestreador muera aunque k6 falle o se interrumpa la corrida.
  trap 'kill "${SAMPLER_PID}" 2>/dev/null || true' EXIT
fi

log "Ejecutando k6 HA02 (4 fases, ~70 min)..."
# k6 sale con código != 0 si algún threshold se incumple — es un resultado
# experimental válido (ver comentario equivalente en run-exp1.sh), no un
# error del script.
if ! PERFILAMIENTO_URL="${PERFILAMIENTO_URL}" k6 run \
  --tag testid=ha02-perfilamiento \
  --out "json=${RESULTS_DIR}/perfilamiento.json" \
  --summary-export="${RESULTS_DIR}/perfilamiento-summary.json" \
  k6/exp2-perfilamiento.js; then
  err "HA02: uno o más thresholds de k6 se incumplieron (ver ${RESULTS_DIR}/perfilamiento-summary.json)."
fi

if [ "${SKIP_K8S_CHECK}" != "true" ]; then
  kill "${SAMPLER_PID}" 2>/dev/null || true
  log "== Capturando estado final del cluster =="
  kubectl describe hpa ms-perfilamiento-hpa -n "${NAMESPACE}" \
    > "${RESULTS_DIR}/hpa-despues.txt" 2>&1 || true
  kubectl get pods -n "${NAMESPACE}" -o wide \
    > "${RESULTS_DIR}/pods-despues.txt" 2>&1 || true
  # OOMKilled / reinicios: el informe pide constatar que no hubo.
  kubectl get events -n "${NAMESPACE}" --sort-by=.lastTimestamp \
    > "${RESULTS_DIR}/events.txt" 2>&1 || true
  kubectl logs -n "${NAMESPACE}" -l app=ms-perfilamiento --tail=500 --prefix \
    > "${RESULTS_DIR}/ms-perfilamiento.log" 2>&1 || true
fi

log "HA02 completo. Resultados en ${RESULTS_DIR}/"
