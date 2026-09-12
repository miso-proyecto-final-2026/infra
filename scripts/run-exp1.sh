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

: "${COTIZACION_URL:=http://localhost:8001}"
: "${MOCK_URL:=http://localhost:8000}"
: "${REDIS_URL:=redis://localhost:6379/0}"

ensure_results_dir
wait_for_pods_running 180

log "== Escenario A: normal (200-500ms) =="
flush_redis
set_mock_latency 200 500

log "Ejecutando k6 Escenario A..."
SCENARIO=A COTIZACION_URL="${COTIZACION_URL}" k6 run \
  --tag testid=ha01-escenario-a \
  --out "json=${RESULTS_DIR}/ha01-escenario-a.json" \
  --summary-export="${RESULTS_DIR}/ha01-escenario-a-summary.json" \
  k6/exp1-cotizacion.js

log "== Escenario B: degradado (800-1500ms) =="
flush_redis
set_mock_latency 800 1500

log "Ejecutando k6 Escenario B..."
SCENARIO=B COTIZACION_URL="${COTIZACION_URL}" k6 run \
  --tag testid=ha01-escenario-b \
  --out "json=${RESULTS_DIR}/ha01-escenario-b.json" \
  --summary-export="${RESULTS_DIR}/ha01-escenario-b-summary.json" \
  k6/exp1-cotizacion.js

log "HA01 completo. Resultados en ${RESULTS_DIR}/ha01-*.json"
