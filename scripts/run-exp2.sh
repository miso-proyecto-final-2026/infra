#!/usr/bin/env bash
# HA02 — Throughput de perfilamiento en línea.
#
# 1. Reconfigura mock a latencia base (300ms fijo)
# 2. Limpia Redis
# 3. Ejecuta k6 con las 4 fases secuenciales (rampa, meseta, sobrecarga, recuperación)
# 4. Exporta resultados
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

RUN_ID="$(date '+%Y%m%d-%H%M%S')"
RESULTS_DIR="${RESULTS_DIR}/${RUN_ID}-ha02"
ensure_results_dir
log "Resultados de esta corrida en: ${RESULTS_DIR}/ (no se sobrescriben entre corridas)"

wait_for_pods_running 180

# En AWS se auto-descubren vía el LoadBalancer de cada Service si no se
# exportan explícitamente; en local (SKIP_K8S_CHECK=true) deben exportarse.
PERFILAMIENTO_URL="$(resolve_service_url PERFILAMIENTO_URL ms-perfilamiento http://localhost:8002)"
MOCK_URL="$(resolve_service_url MOCK_URL mock-open-finance http://localhost:8000)"
REDIS_URL="$(resolve_redis_url 1)"

log "== Configurando mock a latencia base (300ms) =="
set_mock_latency 300 300
flush_redis

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

log "HA02 completo. Resultados en ${RESULTS_DIR}/"
