# Hallazgos de los experimentos

Bitácora viva de hallazgos encontrados al ejecutar HA01/HA02 en AWS real
(no simulado). Cada entrada documenta un síntoma observado, su causa raíz
verificada, y qué se hizo (o se decidió no hacer) al respecto. Sirve como
insumo directo para el análisis de resultados de la Semana 6.

Formato de cada entrada: fecha, experimento afectado, síntoma, causa raíz,
evidencia recolectada, mitigación aplicada (si la hay) y estado.

---

## 2026-09-13 — HA01: `EOF` en requests bajo el NLB de `ms-cotizacion`

**Experimento:** HA01 (latencia de cotización), Escenario A/B, corriendo en
EKS real (no docker-compose).

**Síntoma:** durante la ejecución de `run-exp1.sh` contra el cluster de AWS,
k6 reportó warnings repetidos como:

```
WARN[0621] Request Failed  error="Post \"http://<nlb-dns>:8000/cotizar\": EOF"
```

Estos cuentan como fallos reales de request (no timeouts, no 5xx): la
conexión TCP se cerró a mitad de camino. Impactan directamente la meta de
**0% de cotizaciones fallidas** de HA01.

**Causa raíz verificada:**

`ms-cotizacion` corre con **1 sola réplica** (por diseño explícito de `ms-cotizacion/k8s/deployment.yaml`: la resiliencia del
experimento depende de caché + circuit breaker, no de escalado horizontal —
a diferencia de `ms-perfilamiento`, que sí tiene HPA).

El Service de `ms-cotizacion` es un Network Load Balancer (NLB) de AWS. Se
verificó vía `aws elbv2 describe-target-group-attributes` que el target
group tiene, por defecto:

```
target_health_state.unhealthy.connection_termination.enabled = true
```

Es decir: si el health check del NLB marca el único target como
"unhealthy" — aunque sea por un instante — el NLB **corta inmediatamente
todas las conexiones en curso** hacia ese target, en vez de drenarlas. Con
una sola réplica, no hay un segundo target al cual desviar tráfico mientras
tanto: el corte es total.

El timestamp del primer warning (`t≈621s` de la rampa) coincide con el
momento en que expiran en bloque, por TTL de Redis (`CACHE_TTL_S=300`), las
entradas de caché escritas durante los primeros ~5 minutos de la rampa —
generando una ráfaga simultánea de *cache misses* (thundering herd) que
golpean Open Finance a la vez. Esa ráfaga pudo demorar lo suficiente el
event loop del único pod como para que `/health` respondiera tarde y el
NLB lo marcara unhealthy por un ciclo de chequeo.

**Evidencia recolectada:**
- `kubectl get pods -n solventa-staging -o wide`: 0 reinicios, pod
  `Running` de forma estable durante todo el experimento (no fue un crash
  ni un OOMKilled).
- `kubectl top pod`: en el instante consultado, `ms-cotizacion` usaba
  292m/1000m CPU (29%) — no saturado en ese punto puntual, consistente con
  un bache transitorio y no con agotamiento sostenido de CPU.
- `aws elbv2 describe-target-health`: ambos targets del NLB reportaban
  `healthy` al momento de la revisión posterior (el blip, si ocurrió, ya
  se había autorecuperado).
- `aws elbv2 describe-target-group-attributes`: confirmó
  `target_health_state.unhealthy.connection_termination.enabled = true`
  como configuración activa (default de AWS, no algo que este proyecto
  hubiera fijado explícitamente).

**Mitigación preparada (no aplicada aún — el experimento se dejó correr
sin interrupciones para no invalidar la corrida en curso):**

Se agregaron anotaciones al Service para relajar los umbrales del health
check del NLB, de forma que un bache corto no dispare la desregistración
del único target:

```yaml
# ms-cotizacion/k8s/service.yaml
service.beta.kubernetes.io/aws-load-balancer-healthcheck-interval: "30"
service.beta.kubernetes.io/aws-load-balancer-healthcheck-timeout: "10"
service.beta.kubernetes.io/aws-load-balancer-healthy-threshold: "2"
service.beta.kubernetes.io/aws-load-balancer-unhealthy-threshold: "5"
```

**Estado:** documentado, pendiente de decidir. Dos lecturas válidas para el
informe:

1. **Es un hallazgo de arquitectura legítimo**, no un bug de la app: HA01
   valida caché + circuit breaker asumiendo que 1 pod aguanta la rampa
   completa; el experimento muestra que la política de health-checking del
   load balancer es también parte del sistema y puede introducir fallos
   que el diseño original (a nivel de código) no contempla.
2. Si se prefiere neutralizar el efecto para medir solo la latencia/caché
   (el objetivo original de HA01), aplicar la mitigación de arriba y
   volver a correr para comparar `cotizacion_failed` antes/después.

**Resultados finales de esta corrida** (`results/archive/2026-09-12_ha01-escenario-a/ha01-escenario-a-summary.json`
— el experimento se detuvo después de Escenario A, no llegó a correr
Escenario B degradado):

| Métrica | Meta (CLAUDE.md) | Resultado real | Cumple |
|---|---|---|---|
| `cotizacion_failed` (rate) | `== 0` | **0.6126%** (559 de 91.249 requests) | ❌ |
| `http_req_failed` (rate) | `< 0.1%` | **0.6126%** | ❌ |
| `http_req_duration` p95 (cliente k6) | `≤ 250ms` (normal) | **352.57ms** | ❌ |
| `http_req_duration` p99 (cliente k6) | `≤ 500ms` (normal) | dato no exportado por k6 en este resumen (solo p90/p95) | — |
| `latencia_total_ms` p95 (medido dentro de la app) | — | **258ms** | referencia |
| `cache_hit_rate` | `≥ 60%` desde min. 3 | **94.38%** | ✅ |
| `cotizacion_degradada` | — (0% esperado en Escenario A) | **0%** | ✅ (circuito nunca abrió, correcto para tráfico normal) |

**Hallazgo adicional (nuevo, se suma al de arriba):** el p95 medido por k6
desde el cliente (352.57ms) es ~95ms más alto que el p95 medido dentro de
la propia app (`latencia_total_ms`, 258ms). Esa diferencia es el costo de
red+NLB entre donde corre k6 y el cluster en AWS — si k6 corre fuera de la
VPC (tu máquina local, vía internet hacia el NLB público), esa latencia de
red **se suma** a la que mide la instrumentación interna y **cuenta** para
el threshold `p95≤250ms`, que está definido sobre el tiempo que ve el
cliente, no sobre `latencia_total_ms`. Dos lecturas:
1. Es correcto medirlo así — el usuario real también sufre esa latencia de
   red, por lo que el resultado (❌ no cumple p95≤250ms) es válido tal cual.
2. Si la intención original de la meta era medir solo el desempeño interno
   del servicio (cache+rating+persistencia), correr k6 desde un pod dentro
   del mismo cluster/VPC (en vez de tu máquina) daría un p95 más parecido a
   los 258ms internos — considerar esto al interpretar el resultado.

**Conclusión para el informe:** con la configuración actual (NLB con
health check por defecto + 1 réplica + k6 corriendo fuera de la VPC), HA01
**no cumple** las metas de 0% fallos y p95≤250ms en Escenario A. Las causas
identificadas (health-check del NLB cortando conexiones, y latencia de red
externa sumándose al p95) son ambas explicables y accionables — no indican
un problema en el motor de rating, la caché o el circuit breaker en sí
mismos, que se comportaron correctamente (94% hit rate, 0% degradación
falsa). Pendiente: volver a correr con la mitigación del health check
aplicada (y opcionalmente k6 corriendo dentro del cluster) para ver si las
metas se cumplen, y completar el Escenario B (degradado) que no llegó a
ejecutarse en esta corrida.

---

## 2026-09-13 (actualización) — la hipótesis del health check era incorrecta: el `EOF` es el idle timeout fijo del NLB

**Qué pasó:** se aplicó la mitigación del health check (intervalo 30s,
umbral unhealthy 5, umbral healthy 2 — ver anotaciones en
`ms-cotizacion/k8s/service.yaml`) y se volvió a correr Escenario A desde
cero. El mismo warning volvió a aparecer, casi en el mismo segundo de la
rampa: `t≈608s` en esta corrida vs. `t≈621s` en la anterior (13s de
diferencia, dentro del ruido esperado).

**Por qué eso descarta la hipótesis anterior:** si la causa fuera el
health check marcando el pod "unhealthy" por un bache transitorio de CPU,
relajar los umbrales (ahora se necesitan 5 fallos consecutivos cada 30s =
~150s de mal comportamiento sostenido para desregistrar el target) debería
haber cambiado sustancialmente la frecuencia o el momento del fallo. Que
ocurra casi en el mismo segundo en dos corridas independientes apunta a
algo **determinístico**, no a un blip aleatorio de CPU.

**Causa raíz corregida:** los Network Load Balancer de AWS tienen un
**idle timeout de conexión TCP fijo en 350 segundos, no configurable**
(a diferencia de un ALB/Classic ELB, donde sí se puede ajustar). k6
reutiliza conexiones HTTP keep-alive por VU. Al inicio de la rampa
(`startRate: 500` sol/min, tráfico bajo), muchas VUs preasignadas
(`preAllocatedVUs: 300`) abren su conexión pero no vuelven a usarla
enseguida — si pasan más de 350s sin actividad en esa conexión, el NLB ya
la cerró de su lado. El cliente (k6) no se entera hasta que intenta
reutilizarla para un nuevo request y recibe `EOF` en vez de una respuesta.
Los números cuadran: conexiones abiertas hacia `t≈250-260s` (temprano en
la rampa) + 350s de idle timeout ≈ `t≈600-610s`, que es exactamente donde
aparece el error en ambas corridas.

**Mitigación aplicada:** se agregó `noConnectionReuse: true` a las
`options` de `k6/exp1-cotizacion.js` y `k6/exp2-perfilamiento.js`. Esto
fuerza una conexión TCP nueva por request en vez de reutilizar keep-alive,
eliminando la posibilidad de que el cliente intente usar una conexión que
el NLB ya cerró. Costo: overhead de un handshake TCP adicional por
request, lo que puede subir ligeramente la latencia observada — un
trade-off aceptable frente a tener requests fallando por completo.

**Estado:** corregido el diagnóstico; el fix (`noConnectionReuse`) todavía
no se ha probado en una corrida completa — la corrida en curso al momento
de este hallazgo seguía usando la versión anterior de los scripts (sin
`noConnectionReuse`), así que se espera que también muestre el mismo
`EOF`. **Pendiente:** correr Escenario A de nuevo con el fix ya en los
scripts y confirmar que `cotizacion_failed` baja a 0%.

**Lección para el informe:** la mitigación del health check (relajar
umbrales) no estaba mal en sí — sigue siendo una buena práctica de
resiliencia con 1 sola réplica — pero **no era la causa de este síntoma
específico**. Vale la pena dejar registrado en el informe que la primera
hipótesis fue descartada con evidencia (mismo timestamp en dos corridas
independientes), como ejemplo de método experimental: una mitigación que
no cambia el síntoma es información válida, no un fix fallido a ocultar.

---

## 2026-09-13 — Bug en `run-exp1.sh`: `set -e` aborta la corrida completa si k6 incumple un threshold, saltándose el Escenario B

**Qué pasó:** se corrió `run-exp1.sh` con la versión de scripts anterior
al fix de `noConnectionReuse` (confirmando reproducibilidad: 0.584% de
`cotizacion_failed`, p95 358ms — prácticamente idéntico a la corrida
anterior, 0.61% y 353ms). Al terminar Escenario A, el script **se detuvo
por completo** en vez de seguir con Escenario B: no se ejecutó
`flush_redis` ni `set_mock_latency 800 1500` (se confirmó consultando
`GET /config` del mock, que seguía en `{"min_ms":200,"max_ms":500}`, la
config de Escenario A).

**Causa raíz:** `k6 run` retorna un código de salida distinto de cero
cuando algún threshold definido en el script se incumple (aquí,
`cotizacion_failed: rate==0` y `http_req_failed: rate<0.001`, ambos
violados por las fallas de `EOF` documentadas arriba). Eso es **un
resultado experimental válido** — el experimento corrió completo y generó
datos — no un error del script. Pero `run-exp1.sh` tiene `set -euo
pipefail` al inicio, así que en cuanto k6 sale con código≠0, bash aborta
inmediatamente el resto del script, incluyendo todo el Escenario B.

Esto explica por qué **ninguna de las dos corridas hasta ahora llegó a
ejecutar el Escenario B degradado** — no fue casualidad ni que se
interrumpiera manualmente, era este bug determinístico.

**Mitigación aplicada:** en `scripts/run-exp1.sh` y `scripts/run-exp2.sh`,
cada invocación de `k6 run` ahora está envuelta en `if ! k6 run ...; then
err "..."; fi` — si k6 sale con error, se registra una advertencia clara
(con la ruta al summary para revisar) pero el script continúa con el
siguiente escenario en vez de abortar.

**Estado:** corregido. Pendiente: volver a correr `run-exp1.sh` completo
(con `noConnectionReuse` + este fix) para, esta vez sí, obtener datos
reales del Escenario B (degradado, mock en 800-1500ms, circuito debería
abrir).

**Lección para el informe:** distinguir claramente "el script falló" de
"el experimento corrió y el sistema no cumplió una meta" es importante en
tooling de experimentación — un threshold incumplido es exactamente el
tipo de señal que HA01 está diseñado para capturar, no debería tratarse
como una excepción que aborta el proceso.

---

## 2026-09-12 — HA01 completo (Escenario A + B) con `noConnectionReuse` y el fix de `set -e`: resultados finales

**Corrida:** `run-exp1.sh` completo por primera vez, con ambos fixes ya
aplicados (`k6/exp1-cotizacion.js` con `noConnectionReuse: true`, y los
scripts sin abortar por thresholds). Datos en
`results/archive/2026-09-12_ha01-completo-con-fixes/` (summaries +
crudo). Infra destruida (`teardown.sh`) inmediatamente después — estos son
los números finales de esta ronda de experimentos.

| Métrica | Meta | Escenario A (normal) | Escenario B (degradado) |
|---|---|---|---|
| `cotizacion_failed` / `http_req_failed` | 0% | **0%** ✅ | **0%** ✅ |
| `http_req_duration` p95 (cliente) | ≤250ms / ≤300ms | **357.6ms** ❌ | **123.9ms** ✅ |
| `http_req_duration` p99 (cliente) | ≤500ms (solo normal) | **565.3ms** ❌ | 829.7ms (sin meta definida para degradado) |
| `cache_hit_rate` | ≥60% desde min. 3 | **94.4%** ✅ | 0% (ver nota) |
| `cotizacion_degradada` | — | 0% ✅ (esperado, circuito cerrado) | **100%** ✅ |

p99 se calculó aparte (no viene en el `--summary-export` por defecto de
k6, solo exporta p90/p95): se extrajo con `jq` filtrando
`metric=="http_req_duration"` + `tags.scenario_tag` del archivo crudo
(`--out json=...`) y percentil calculado en Python sobre los 91.249
valores de cada escenario.

**El resultado central de HA01 se cumplió:** el circuit breaker + caché
lograron **0% de cotizaciones fallidas incluso con Open Finance
100% degradado** (100% de las cotizaciones en Escenario B salieron
marcadas `degradada=true`, ninguna falló). Esa es la hipótesis de diseño
que este experimento existe para validar, y se validó.

**Lo que no se cumplió — dos hallazgos de latencia, no de disponibilidad:**

1. **p95/p99 en Escenario A (normal) exceden la meta** (357.6ms/565.3ms
   vs. 250ms/500ms). De ese exceso, un componente ya identificado
   (hallazgo de 2026-09-13 arriba) es la latencia de red entre k6 —
   corriendo fuera de la VPC, contra el DNS público del NLB— y el cluster:
   la propia app mide internamente p95≈261ms (`latencia_total_ms`), mucho
   más cerca de la meta que los 357.6ms que ve k6. El resto de la brecha
   (261ms vs. 250ms) es un exceso real, aunque pequeño, del propio
   servicio bajo carga plena (5.000 sol/min).
2. **p99 en Escenario B es alto (829.7ms) pese a que el p95 es excelente
   (123.9ms)** — no incumple ninguna meta explícita (HA01 no define p99
   para degradado), pero es una cola larga notoria. Hipótesis más probable
   (no verificada con logs/trazas en esta ronda): los reintentos
   periódicos de `pybreaker` cada `CB_RESET_TIMEOUT_S=30s` (el circuito
   pasa a *half-open* y prueba una llamada real a Open Finance, que sigue
   tardando 800-1500ms y volviendo a fallar) generan picos de latencia
   recurrentes a lo largo de los 25 minutos de la corrida, sin afectar al
   grueso de las requests que sí se resuelven casi instantáneo desde caché
   stale/default.

**Estado:** HA01 ejecutado exitosamente de punta a punta con datos
válidos y reproducibles. Meta de disponibilidad (0% fallos) **cumplida**.
Metas de latencia en operación normal **no cumplidas** por un margen
moderado — queda como hallazgo de arquitectura para el informe, con dos
hipótesis de causa ya identificadas (overhead de red externa + posible
efecto del backoff del circuit breaker) que se pueden profundizar en una
próxima ronda si se vuelve a levantar la infra (con OpenTelemetry/Grafana
ya conectado, para correlacionar los picos de p99 con los ciclos de
half-open del breaker en vez de inferirlo).
