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
import exec from 'k6/execution';
import { check } from 'k6';
import { SharedArray } from 'k6/data';
import { Rate, Trend } from 'k6/metrics';

const BASE_URL = __ENV.PERFILAMIENTO_URL || 'http://localhost:8002';

// HA02_SMOKE=true corre las 4 fases comprimidas (~5 min en vez de ~70) para
// validar de punta a punta que el tagging, los thresholds, el dataset y el
// muestreo del HPA funcionan ANTES de gastar 70 minutos de cluster. Los
// cortes de fase se escalan con el mismo factor (ver faseCortes).
const SMOKE = (__ENV.HA02_SMOKE || '').toLowerCase() === 'true';
const F = SMOKE ? 1 / 14 : 1; // 70 min -> 5 min

// Cortes de fase en minutos: [fin rampa, fin línea base, fin meseta, fin sobrecarga]
const faseCortes = [15 * F, 20 * F, 50 * F, 60 * F];

function dur(min) {
  return `${Math.max(1, Math.round(min * F * 60))}s`;
}

const profiles = new SharedArray('profiles_exp2', function () {
  return JSON.parse(open('./data/profiles_exp2.json'));
});

export const perfilarFailed = new Rate('perfilar_failed');
export const cacheHitRate = new Rate('cache_hit_rate');
export const latenciaTotal = new Trend('latencia_total_ms', true);

export const options = {
  // Ver comentario equivalente en exp1-cotizacion.js: el NLB de AWS cierra
  // conexiones TCP inactivas a los 350s (fijo, no configurable); se evita
  // reutilizar conexiones potencialmente muertas (ver docs/hallazgos.md).
  noConnectionReuse: true,
  scenarios: {
    perfilamiento: {
      executor: 'ramping-arrival-rate',
      startRate: 0,
      timeUnit: '1h',
      preAllocatedVUs: 100,
      maxVUs: 500,
      stages: [
        { target: 20000, duration: dur(20) }, // fase 1: rampa (incl. línea base)
        { target: 20000, duration: dur(30) }, // fase 2: meseta
        { target: 25000, duration: dur(10) }, // fase 3: sobrecarga
        { target: 0, duration: dur(10) },     // fase 4: recuperación
      ],
    },
  },
  thresholds: {
    'http_req_failed': ['rate<0.01'],
    'http_req_duration{fase:meseta}': ['p(95)<500'],
  },
};

// Etiqueta la fase actual según el tiempo transcurrido desde el arranque
// del test, para poder filtrar/comparar el p95 de cada fase al analizar.
//
// Se usa exec.instance.currentTestRunDuration (ms desde que arrancó la
// corrida, idéntico para todos los VUs) y NO un Date.now() guardado en
// globalThis: cada VU de k6 corre en su propio runtime JS y se inicializa
// perezosamente a medida que sube la tasa de llegada, así que un VU que
// arranca en el minuto 30 habría fijado su propio "t0" en el minuto 30 y
// habría etiquetado sus requests como 'rampa' durante media corrida.
//
// Los minutos 15-20 (últimos 5 de la rampa, ya a 20.000/h) se etiquetan
// aparte como 'linea_base': es contra ese p95 que se compara la meseta
// para la meta de "degradación <= 10%".
function currentFase() {
  const t = exec.instance.currentTestRunDuration / 60000;
  if (t < faseCortes[0]) return 'rampa';
  if (t < faseCortes[1]) return 'linea_base';
  if (t < faseCortes[2]) return 'meseta';
  if (t < faseCortes[3]) return 'sobrecarga';
  return 'recuperacion';
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
