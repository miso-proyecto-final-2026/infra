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

: "${PERFILAMIENTO_URL:=http://localhost:8002}"
: "${MOCK_URL:=http://localhost:8000}"
: "${REDIS_URL:=redis://localhost:6379/1}"

ensure_results_dir
wait_for_pods_running 180

log "== Configurando mock a latencia base (300ms) =="
set_mock_latency 300 300
flush_redis

log "Ejecutando k6 HA02 (4 fases, ~70 min)..."
PERFILAMIENTO_URL="${PERFILAMIENTO_URL}" k6 run \
  --tag testid=ha02-perfilamiento \
  --out "json=${RESULTS_DIR}/ha02-perfilamiento.json" \
  --summary-export="${RESULTS_DIR}/ha02-perfilamiento-summary.json" \
  k6/exp2-perfilamiento.js

log "HA02 completo. Resultados en ${RESULTS_DIR}/ha02-perfilamiento*.json"
