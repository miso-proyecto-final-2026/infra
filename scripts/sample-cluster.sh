#!/usr/bin/env bash
# Muestrea el estado del HPA, las réplicas y el consumo de CPU/memoria de
# ms-perfilamiento durante una corrida, a un archivo CSV por muestra.
#
# Existe porque el stack de observabilidad (otel-collector -> tempo/prometheus
# -> Grafana) NO está desplegado en el cluster: el collector exporta a
# `tempo:4317` y `prometheus:9090`, que no existen como Services. Sin esto,
# una corrida de HA02 termina sin ninguna evidencia de escalado, que es
# exactamente lo que el informe pide registrar (réplicas al final de la
# rampa, réplicas estabilizadas, CPU por réplica, OOMKilled).
#
# Uso:  ./scripts/sample-cluster.sh <archivo-salida.csv> [intervalo_s]
# Se detiene con SIGTERM/SIGINT (run-exp2.sh lo mata al terminar k6).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

OUT="${1:?uso: sample-cluster.sh <archivo-salida.csv> [intervalo_s]}"
INTERVAL="${2:-15}"
APP="${APP:-ms-perfilamiento}"
HPA="${HPA:-ms-perfilamiento-hpa}"

echo "timestamp,replicas_ready,hpa_current_replicas,hpa_desired_replicas,hpa_min,hpa_max,hpa_cpu_pct,pods_running,pods_pending,pods_no_running,restarts_total,cpu_total_m,mem_total_mi,pod_cpu_detalle" > "${OUT}"

trap 'exit 0' TERM INT

while true; do
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"

  # --- HPA: por jsonpath y no parseando la tabla humana, porque la columna
  # TARGETS se imprime como "cpu: 4%/70%" (dos campos separados por espacio)
  # y cualquier awk por posición sale corrido.
  hpa="$(kubectl get hpa "${HPA}" -n "${NAMESPACE}" -o jsonpath='{.status.currentReplicas} {.status.desiredReplicas} {.spec.minReplicas} {.spec.maxReplicas} {.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || true)"
  read -r hpa_current hpa_desired hpa_min hpa_max hpa_cpu <<<"${hpa}"

  # --- Pods del deployment
  pods="$(kubectl get pods -n "${NAMESPACE}" -l "app=${APP}" --no-headers 2>/dev/null || true)"
  pods_running="$(awk '$3=="Running"' <<<"${pods}" | grep -c . || true)"
  pods_pending="$(awk '$3=="Pending"' <<<"${pods}" | grep -c . || true)"
  pods_otros="$(awk 'NF && $3!="Running" && $3!="Pending"' <<<"${pods}" | grep -c . || true)"
  # READY 1/1 -> cuenta como listo
  replicas_ready="$(awk '{split($2,a,"/"); if (a[1]==a[2] && $3=="Running") c++} END{print c+0}' <<<"${pods}")"
  restarts="$(awk '{s+=$4} END{print s+0}' <<<"${pods}")"

  # --- Consumo real (requiere metrics-server, que instala Terraform)
  top="$(kubectl top pods -n "${NAMESPACE}" -l "app=${APP}" --no-headers 2>/dev/null || true)"
  cpu_total="$(awk '{gsub(/m$/,"",$2); s+=$2} END{print s+0}' <<<"${top}")"
  mem_total="$(awk '{gsub(/Mi$/,"",$3); s+=$3} END{print s+0}' <<<"${top}")"
  detalle="$(awk '{printf "%s=%s ", $1, $2}' <<<"${top}" | sed 's/ $//')"

  echo "${ts},${replicas_ready},${hpa_current:-},${hpa_desired:-},${hpa_min:-},${hpa_max:-},${hpa_cpu:-},${pods_running},${pods_pending},${pods_otros},${restarts},${cpu_total},${mem_total},\"${detalle}\"" >> "${OUT}"
  sleep "${INTERVAL}"
done
