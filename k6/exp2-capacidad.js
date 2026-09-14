/**
 * HA02 — Corrida de capacidad (complementaria al experimento del diseño).
 *
 * POR QUÉ EXISTE
 * --------------
 * La corrida de las 4 fases de `exp2-perfilamiento.js` valida RQ-E1.2
 * (>= 20.000 perfilamientos/hora) y lo cumple, pero NO produce evidencia
 * sobre el HPA: medido en la corrida del 2026-09-13, la utilización de CPU
 * se quedó en 4,2% de media y 7% de pico frente al umbral del 70%, y el
 * autoescalado nunca salió de minReplicas: 2 en 224 muestras.
 *
 * Esta corrida sube la tasa hasta forzar el escalado, para responder lo que
 * la hipótesis de HA02 realmente pregunta: ¿el HPA absorbe las ráfagas, en
 * cuánto tiempo, y hasta dónde?
 *
 * DIMENSIONAMIENTO
 * ----------------
 * Medido en meseta: ~14,6 milicores de CPU por solicitud/s. El umbral del
 * HPA son 700m (70% del request de 500m x 2 réplicas), lo que da ~48 sol/s
 * ≈ 173.000/hora como punto de activación estimado.
 *
 * Esa estimación tiene una incertidumbre conocida: a tasas altas el hit de
 * caché sube (con 5.000 claves y TTL de 900s, por encima de ~100 sol/s casi
 * todo sale de caché), y una solicitud servida desde caché no llama a Open
 * Finance, así que cuesta menos CPU. El costo por solicitud puede bajar y
 * mover el punto de activación hacia arriba.
 *
 * Por eso la rampa NO apunta a una tasa calculada: sube de forma sostenida
 * hasta muy por encima del estimado y deja que el muestreo del cluster
 * registre dónde ocurre el escalado de verdad. Se mide, no se predice.
 *
 * Techo esperado: con 3 nodos t3.medium y ~4.590m de CPU asignable libre,
 * caben ~9 réplicas de 500m. El HPA declara maxReplicas: 10, así que el
 * límite lo debería poner el cluster, no el manifiesto — parte de lo que
 * esta corrida busca confirmar.
 *
 * Duración total: ~20 min.
 */
import http from 'k6/http';
import exec from 'k6/execution';
import { check } from 'k6';
import { SharedArray } from 'k6/data';
import { Rate, Trend } from 'k6/metrics';

const BASE_URL = __ENV.PERFILAMIENTO_URL || 'http://localhost:8002';

// Tasa máxima de la rampa, en perfilamientos/hora. Se puede subir por
// entorno si la corrida muestra que el sistema aguanta más sin escalar.
const TASA_MAX = parseInt(__ENV.TASA_MAX || '600000', 10);

const profiles = new SharedArray('profiles_cap', function () {
  return JSON.parse(open('./data/profiles_exp2.json'));
});

export const perfilarFailed = new Rate('perfilar_failed');
export const cacheHitRate = new Rate('cache_hit_rate');
export const latenciaTotal = new Trend('latencia_total_ms', true);

export const options = {
  // Igual que en las otras corridas: el NLB cierra conexiones TCP inactivas
  // a los 350s (fijo, no configurable) y k6 no se entera hasta reutilizarlas
  // (ver docs/hallazgos.md). Se mantiene además por comparabilidad: las tres
  // corridas pagan el mismo overhead de handshake por solicitud.
  noConnectionReuse: true,
  scenarios: {
    capacidad: {
      executor: 'ramping-arrival-rate',
      startRate: 20000,
      timeUnit: '1h',
      // Holgura amplia: si la latencia se degrada al saturar, cada solicitud
      // ocupa su VU más tiempo y hacen falta muchos más para sostener la
      // tasa. Quedarse corto haría que k6 no alcance el objetivo y se
      // confundiría "el sistema no da" con "el generador no da".
      preAllocatedVUs: 200,
      maxVUs: 1500,
      stages: [
        { target: TASA_MAX, duration: '12m' }, // rampa sostenida hasta saturar
        { target: TASA_MAX, duration: '5m' },  // meseta en el máximo
        { target: 0, duration: '3m' },         // recuperación
      ],
    },
  },
  // Sin thresholds de latencia a propósito: esta corrida busca encontrar el
  // punto de quiebre, no verificar que no exista. Un p95 alto al final de la
  // rampa es el resultado esperado, no un fallo.
  thresholds: {
    'http_req_failed': ['rate<0.50'],
  },
};

function faseActual() {
  const t = exec.instance.currentTestRunDuration / 60000;
  if (t < 12) return 'rampa';
  if (t < 17) return 'meseta_max';
  return 'recuperacion';
}

export default function () {
  const profile = profiles[Math.floor(Math.random() * profiles.length)];

  const res = http.post(
    `${BASE_URL}/perfilar`,
    JSON.stringify({
      client_id: profile.client_id,
      consentimiento_id: profile.consentimiento_id,
    }),
    {
      headers: { 'Content-Type': 'application/json' },
      tags: { fase: faseActual(), experimento: 'HA02-capacidad' },
    }
  );

  const ok = check(res, { 'status 200': (r) => r.status === 200 });
  perfilarFailed.add(!ok);

  if (ok) {
    const body = JSON.parse(res.body);
    cacheHitRate.add(body.hit_cache === true);
    latenciaTotal.add(body.tiempo_total_ms);
  }
}
