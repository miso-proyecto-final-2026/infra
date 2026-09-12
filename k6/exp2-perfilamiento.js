/**
 * HA02 — Throughput de perfilamiento en línea.
 *
 * Fases:
 *   1. Rampa:      0 -> 20.000 perf/hora durante 20 min
 *   2. Meseta:     20.000 perf/hora durante 30 min
 *   3. Sobrecarga: 25.000 perf/hora durante 10 min
 *   4. Recuperación: apagar generador (target 0), medir recuperación del p95
 *
 * Metas: throughput >= 20.000/hora sostenido, p95 no se degrada > 10%
 * respecto de la línea base, réplicas HPA estables, hit de caché >= 40%.
 */
import http from 'k6/http';
import { check } from 'k6';
import { SharedArray } from 'k6/data';
import { Rate, Trend } from 'k6/metrics';

const BASE_URL = __ENV.PERFILAMIENTO_URL || 'http://localhost:8002';

const profiles = new SharedArray('profiles_exp2', function () {
  return JSON.parse(open('./data/profiles_exp2.json'));
});

export const perfilarFailed = new Rate('perfilar_failed');
export const cacheHitRate = new Rate('cache_hit_rate');
export const latenciaTotal = new Trend('latencia_total_ms', true);

export const options = {
  scenarios: {
    perfilamiento: {
      executor: 'ramping-arrival-rate',
      startRate: 0,
      timeUnit: '1h',
      preAllocatedVUs: 100,
      maxVUs: 500,
      stages: [
        { target: 20000, duration: '20m' }, // fase 1: rampa
        { target: 20000, duration: '30m' }, // fase 2: meseta
        { target: 25000, duration: '10m' }, // fase 3: sobrecarga
        { target: 0, duration: '10m' },     // fase 4: recuperación
      ],
    },
  },
  thresholds: {
    'http_req_failed': ['rate<0.01'],
    'http_req_duration{fase:meseta}': ['p(95)<500'],
  },
};

// Etiqueta la fase actual según el tiempo transcurrido, para poder
// filtrar/comparar el p95 de meseta vs. sobrecarga vs. recuperación en Grafana.
function currentFase() {
  const t = __ITER >= 0 ? exec_time_min() : 0;
  if (t < 20) return 'rampa';
  if (t < 50) return 'meseta';
  if (t < 60) return 'sobrecarga';
  return 'recuperacion';
}

function exec_time_min() {
  // __VU/__ITER no exponen tiempo de reloj directamente; se usa Date.now()
  // relativo al arranque del script (aproximación suficiente para tagging).
  if (!globalThis.__start) globalThis.__start = Date.now();
  return (Date.now() - globalThis.__start) / 60000;
}

export default function () {
  const profile = profiles[Math.floor(Math.random() * profiles.length)];
  const fase = currentFase();

  const res = http.post(
    `${BASE_URL}/perfilar`,
    JSON.stringify({
      client_id: profile.client_id,
      consentimiento_id: profile.consentimiento_id,
    }),
    {
      headers: { 'Content-Type': 'application/json' },
      tags: { fase, experimento: 'HA02' },
    }
  );

  const ok = check(res, {
    'status 200': (r) => r.status === 200,
  });

  perfilarFailed.add(!ok);

  if (ok) {
    const body = JSON.parse(res.body);
    cacheHitRate.add(body.hit_cache === true);
    latenciaTotal.add(body.tiempo_total_ms);
  }
}
