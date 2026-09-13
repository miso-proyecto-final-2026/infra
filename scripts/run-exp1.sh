#!/usr/bin/env bash
# HA01 — Latencia de cotización con Open Finance degradado.
#
# 1. Verifica pods Running
# 2. Limpia Redis
# 3. Configura mock en latencia normal (200-500ms)
# 4. Ejecuta k6 Escenario A (rampa + meseta)
# 5. Exporta resultados a JSON
# 6. Limpia Redis
# 7. Reconfigura mock a degradado (800-1500ms)
# 8. Ejecuta k6 Escenario B (misma rampa + meseta)
# 9. Exporta resultados
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

RUN_ID="$(date '+%Y%m%d-%H%M%S')"
RESULTS_DIR="${RESULTS_DIR}/${RUN_ID}-ha01"
ensure_results_dir
log "Resultados de esta corrida en: ${RESULTS_DIR}/ (no se sobrescriben entre corridas)"

wait_for_pods_running 180

# En AWS se auto-descubren vía el LoadBalancer de cada Service si no se
# exportan explícitamente; en local (SKIP_K8S_CHECK=true) deben exportarse.
COTIZACION_URL="$(resolve_service_url COTIZACION_URL ms-cotizacion http://localhost:8001)"
MOCK_URL="$(resolve_service_url MOCK_URL mock-open-finance http://localhost:8000)"
REDIS_URL="$(resolve_redis_url 0)"

log "== Escenario A: normal (200-500ms) =="
flush_redis
set_mock_latency 200 500

log "Ejecutando k6 Escenario A..."
# k6 sale con código != 0 si algún threshold se incumple (p.ej.
# cotizacion_failed > 0) — eso es un resultado experimental válido, no un
# error del script. No dejamos que aborte la corrida (Escenario B debe
# ejecutarse igual); solo lo advertimos y seguimos.
if ! SCENARIO=A COTIZACION_URL="${COTIZACION_URL}" k6 run \
  --tag testid=ha01-escenario-a \
  --out "json=${RESULTS_DIR}/escenario-a.json" \
  --summary-export="${RESULTS_DIR}/escenario-a-summary.json" \
  k6/exp1-cotizacion.js; then
  err "Escenario A: uno o más thresholds de k6 se incumplieron (ver ${RESULTS_DIR}/escenario-a-summary.json). Continuando con Escenario B."
fi

log "== Escenario B: degradado (800-1500ms) =="
flush_redis
set_mock_latency 800 1500

log "Ejecutando k6 Escenario B..."
if ! SCENARIO=B COTIZACION_URL="${COTIZACION_URL}" k6 run \
  --tag testid=ha01-escenario-b \
  --out "json=${RESULTS_DIR}/escenario-b.json" \
  --summary-export="${RESULTS_DIR}/escenario-b-summary.json" \
  k6/exp1-cotizacion.js; then
  err "Escenario B: uno o más thresholds de k6 se incumplieron (ver ${RESULTS_DIR}/escenario-b-summary.json)."
fi

log "HA01 completo. Resultados en ${RESULTS_DIR}/"
