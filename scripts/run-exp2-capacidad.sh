#!/usr/bin/env bash
# HA02 — Corrida de capacidad (complementaria a run-exp2.sh).
#
# Sube la tasa hasta forzar el escalado del HPA, para obtener la evidencia de
# autoescalado que la corrida de las 4 fases del diseño no produce (ahí el
# HPA se queda en minReplicas: 2 con 4% de utilización). Ver la cabecera de
# k6/exp2-capacidad.js para el dimensionamiento.
#
# Los resultados van a results/<timestamp>-ha02-capacidad/, separados de los
# de run-exp2.sh (que usa el sufijo -ha02), así que ninguna corrida pisa a
# la otra.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

RUN_ID="$(date '+%Y%m%d-%H%M%S')"
RESULTS_DIR="${RESULTS_DIR}/${RUN_ID}-ha02-capacidad"
ensure_results_dir
log "Resultados de esta corrida en: ${RESULTS_DIR}/"

if [ ! -f k6/data/profiles_exp2.json ]; then
  log "k6/data/profiles_exp2.json no existe; generando datasets sintéticos..."
  python3 k6/data/generate_data.py
fi

wait_for_pods_running 180

PERFILAMIENTO_URL="$(resolve_service_url PERFILAMIENTO_URL ms-perfilamiento http://localhost:8002)"
MOCK_URL="$(resolve_service_url MOCK_URL mock-open-finance http://localhost:8000)"
REDIS_URL="$(resolve_redis_url 1)"

log "== Configurando mock a latencia base (300ms) =="
set_mock_latency 300 300

# Caché limpia: arrancar con caché caliente de una corrida previa falsearía
# el costo por solicitud y movería el punto de activación del HPA.
flush_redis

if [ "${SKIP_K8S_CHECK}" != "true" ]; then
  kubectl describe hpa ms-perfilamiento-hpa -n "${NAMESPACE}" \
    > "${RESULTS_DIR}/hpa-antes.txt" 2>&1 || true
  kubectl get nodes -o wide > "${RESULTS_DIR}/nodes.txt" 2>&1 || true
  kubectl describe nodes | grep -A 8 "Allocated resources" \
    > "${RESULTS_DIR}/nodes-allocated-antes.txt" 2>&1 || true

  # Muestreo cada 10s en vez de 15s: lo que interesa aquí son los eventos de
  # escalado, que duran poco y se pierden con un intervalo grueso.
  log "== Arrancando muestreo de ms-perfilamiento cada 10s =="
  ./scripts/sample-cluster.sh "${RESULTS_DIR}/cluster-samples.csv" 10 &
  SAMPLER_PID=$!

  # Segundo muestreo sobre el mock: a tasas altas el stub puede saturarse
  # antes que el servicio bajo prueba, y sin este dato se estaría midiendo
  # el cuello de botella equivocado. No tiene HPA, así que esas columnas
  # salen vacías.
  log "== Arrancando muestreo de mock-open-finance cada 10s =="
  APP=mock-open-finance HPA=no-existe \
    ./scripts/sample-cluster.sh "${RESULTS_DIR}/mock-samples.csv" 10 &
  SAMPLER_MOCK_PID=$!

  trap 'kill "${SAMPLER_PID}" "${SAMPLER_MOCK_PID}" 2>/dev/null || true' EXIT
fi

log "Ejecutando k6 HA02-capacidad (rampa 12m + meseta 5m + bajada 3m)..."
if ! PERFILAMIENTO_URL="${PERFILAMIENTO_URL}" k6 run \
  --tag testid=ha02-capacidad \
  --out "json=${RESULTS_DIR}/capacidad.json" \
  --summary-export="${RESULTS_DIR}/capacidad-summary.json" \
  k6/exp2-capacidad.js; then
  err "HA02-capacidad: algún threshold se incumplió (ver ${RESULTS_DIR}/capacidad-summary.json)."
fi

if [ "${SKIP_K8S_CHECK}" != "true" ]; then
  kill "${SAMPLER_PID}" "${SAMPLER_MOCK_PID}" 2>/dev/null || true
  log "== Capturando estado final del cluster =="
  kubectl describe hpa ms-perfilamiento-hpa -n "${NAMESPACE}" \
    > "${RESULTS_DIR}/hpa-despues.txt" 2>&1 || true
  kubectl get pods -n "${NAMESPACE}" -o wide \
    > "${RESULTS_DIR}/pods-despues.txt" 2>&1 || true
  # Los eventos registran los scale-up/scale-down del HPA y cualquier pod
  # que no haya cabido en los nodos (FailedScheduling), que es justo el
  # techo que esta corrida busca localizar.
  kubectl get events -n "${NAMESPACE}" --sort-by=.lastTimestamp \
    > "${RESULTS_DIR}/events.txt" 2>&1 || true
  kubectl describe nodes | grep -A 8 "Allocated resources" \
    > "${RESULTS_DIR}/nodes-allocated-despues.txt" 2>&1 || true
  kubectl logs -n "${NAMESPACE}" -l app=ms-perfilamiento --tail=500 --prefix \
    > "${RESULTS_DIR}/ms-perfilamiento.log" 2>&1 || true
fi

log "HA02-capacidad completo. Resultados en ${RESULTS_DIR}/"
