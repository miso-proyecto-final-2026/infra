/**
 * HA01 — Latencia de cotización con Open Finance degradado.
 *
 * Carga: rampa 500 -> 5.000 sol/min durante 15 min, meseta 5.000 sol/min
 * durante 10 min. El escenario (A: normal / B: degradado) se controla
 * externamente reconfigurando la latencia del mock antes de invocar este
 * script (ver scripts/run-exp1.sh); se etiqueta vía la env var SCENARIO
 * para poder filtrar en Grafana.
 *
 * Metas (ver CLAUDE.md):
 *   p95 <= 250ms / p99 <= 500ms en normal, p95 <= 300ms en degradado,
 *   0% de cotizaciones fallidas, hit de caché >= 60% desde el minuto 3.
 */
import http from 'k6/http';
import { check } from 'k6';
import { SharedArray } from 'k6/data';
import { Rate, Trend } from 'k6/metrics';

const BASE_URL = __ENV.COTIZACION_URL || 'http://localhost:8001';
const SCENARIO = __ENV.SCENARIO || 'A';

const profiles = new SharedArray('profiles_exp1', function () {
  return JSON.parse(open('./data/profiles_exp1.json'));
});

export const cotizacionFailed = new Rate('cotizacion_failed');
export const cotizacionDegradada = new Rate('cotizacion_degradada');
export const cacheHitRate = new Rate('cache_hit_rate');
export const latenciaTotal = new Trend('latencia_total_ms', true);

export const options = {
  scenarios: {
    cotizacion: {
      executor: 'ramping-arrival-rate',
      startRate: 500,
      timeUnit: '1m',
      preAllocatedVUs: 300,
      maxVUs: 1500,
      stages: [
        { target: 5000, duration: '15m' }, // rampa
        { target: 5000, duration: '10m' }, // meseta
      ],
    },
  },
  thresholds: {
    'http_req_failed': ['rate<0.001'],
    'cotizacion_failed': ['rate==0'],
    'http_req_duration{scenario_tag:A}': ['p(95)<250', 'p(99)<500'],
    'http_req_duration{scenario_tag:B}': ['p(95)<300'],
  },
};

export default function () {
  const profile = profiles[Math.floor(Math.random() * profiles.length)];

  const res = http.post(
    `${BASE_URL}/cotizar`,
    JSON.stringify({ client_id: profile.client_id }),
    {
      headers: { 'Content-Type': 'application/json' },
      tags: { scenario_tag: SCENARIO, experimento: 'HA01' },
    }
  );

  const ok = check(res, {
    'status 200': (r) => r.status === 200,
    'tiene prima_mensual': (r) => {
      try {
        return JSON.parse(r.body).prima_mensual > 0;
      } catch {
        return false;
      }
    },
  });

  cotizacionFailed.add(!ok);

  if (ok) {
    const body = JSON.parse(res.body);
    cacheHitRate.add(body.hit_cache === true);
    cotizacionDegradada.add(body.degradada === true);
    latenciaTotal.add(body.tiempo_total_ms);
  }
}
