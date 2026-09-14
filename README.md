# solventa-experimentos

Experimentos de arquitectura de la Semana 6 (MISW4501, Grupo 10) para validar
hipótesis de diseño del Sprint 1 de **Solventa**, insurtech de Open Finance
para seguros de vida hipotecario. Ver [`CLAUDE.md`](./CLAUDE.md) para el
contexto completo y las metas de cada experimento.

## Experimentos

- **HA01** — Latencia de cotización con Open Finance degradado (cache-aside
  + circuit breaker con `pybreaker`). Metas: p95 ≤ 250ms / p99 ≤ 500ms en
  normal, p95 ≤ 300ms en degradado, 0% de fallos, hit de caché ≥ 60%.
- **HA02** — Throughput de perfilamiento en línea (cache-aside + HPA, sin
  circuit breaker). Meta: ≥ 20.000 perfilamientos/hora sostenidos, p95 sin
  degradarse > 10%, hit de caché ≥ 40%.

## Documentación

- [`docs/hallazgos.md`](./docs/hallazgos.md) — bitácora viva de hallazgos: cada
  síntoma observado durante las corridas, su causa raíz verificada y la
  mitigación aplicada o descartada.
- [`docs/resultados-finales-experimentacion.md`](./docs/resultados-finales-experimentacion.md)
  — resultados finales de HA01 y HA02, análisis de cumplimiento de las
  hipótesis de diseño y decisiones de arquitectura derivadas.

## Estructura

```
mock-open-finance/   Stub FastAPI de Open Finance con latencia inyectable
ms-cotizacion/        FastAPI + Redis + pybreaker + PostgreSQL + OTel (HA01)
ms-perfilamiento/     FastAPI + Redis + HPA + OTel (HA02)
k6/                   Scripts de carga y generador de datasets sintéticos
infra/terraform/      VPC, EKS + node group, ECR, ElastiCache Redis, RDS PostgreSQL
observability/        OpenTelemetry Collector + dashboards de Grafana
db/init.sql           Esquema PostgreSQL (cotizacion, log_latencia)
scripts/              setup.sh, run-exp1.sh, run-exp2.sh, teardown.sh
```

## Correr localmente (sin Kubernetes)

Requiere Docker, Docker Compose y [k6](https://k6.io/docs/get-started/installation/).

```bash
# 1. Generar datasets sintéticos (ya incluidos en el repo, regenerar si hace falta)
python3 k6/data/generate_data.py

# 2. Levantar el stack
docker compose up --build -d

# 3. Correr HA01 (Escenario A + B) contra el stack local
SKIP_K8S_CHECK=true COTIZACION_URL=http://localhost:8001 MOCK_URL=http://localhost:8000 \
  REDIS_URL=redis://localhost:6379/0 ./scripts/run-exp1.sh

# 4. Correr HA02 contra el stack local
SKIP_K8S_CHECK=true PERFILAMIENTO_URL=http://localhost:8002 MOCK_URL=http://localhost:8000 \
  REDIS_URL=redis://localhost:6379/1 ./scripts/run-exp2.sh
```

`run-exp1.sh` y `run-exp2.sh` llaman `wait_for_pods_running` y `flush_redis`,
que por defecto usan `kubectl` apuntando a un cluster. Para correr contra
`docker compose` sin Kubernetes, exportar `SKIP_K8S_CHECK=true`: se omite la
verificación de pods y `flush_redis` usa `redis-cli` directo contra
`REDIS_URL` (ver `scripts/lib.sh`).

## Correr en AWS (staging) — infra 100% Terraform

Terraform crea **todo** desde cero: VPC (2 AZs, NAT único), cluster EKS +
node group administrado, repositorios ECR, ElastiCache Redis, RDS
PostgreSQL, el namespace de Kubernetes y `metrics-server` (vía Helm, requerido
por el HPA de `ms-perfilamiento`). No asume que ya exista un cluster.

**Prerrequisitos en tu máquina:** `terraform` >= 1.5, `aws` CLI autenticado
contra tu cuenta (`aws sts get-caller-identity` debe funcionar), `kubectl`,
`docker`, `envsubst` (paquete `gettext-base`, ya viene en la mayoría de
distros Ubuntu/Debian).

```bash
# 1. Configurar variables (opcional, hay defaults razonables)
cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars
# editar región, tamaño de nodos, etc. si hace falta

# 2. Password de RDS: nunca en el tfvars, siempre por variable de entorno
export TF_VAR_db_password='elige-un-password-seguro'

# 3. Levantar TODO: terraform apply (~15-20 min por el cluster EKS) +
#    apuntar kubectl al cluster + build&push de las 3 imágenes a ECR +
#    aplicar los manifiestos de Kubernetes
./scripts/setup.sh

# 4. Ejecutar los experimentos (kubectl ya apunta al cluster de AWS)
./scripts/run-exp1.sh
./scripts/run-exp2.sh
# nota: los Services de mock-open-finance, ms-cotizacion y ms-perfilamiento
# son LoadBalancer (NLB en los dos últimos), así que no hace falta
# port-forward. setup.sh espera a que AWS asigne el hostname del LB y lo
# imprime al final; run-exp1.sh/run-exp2.sh también lo autodescubren solos
# si no exportas COTIZACION_URL/PERFILAMIENTO_URL/MOCK_URL a mano.

# 5. Apagar TODO al terminar (control de créditos AWS: EKS + nodos + NAT
#    gateway + RDS + ElastiCache tienen costo por hora mientras estén arriba)
./scripts/teardown.sh
```

Si ya tienes un cluster EKS y prefieres reusarlo en lugar de crear uno nuevo,
dime y ajusto `infra/terraform/eks.tf`/`vpc.tf` para apuntar a recursos
existentes vía `data` sources en lugar de crearlos.

## Tests unitarios

```bash
cd mock-open-finance && pip install -r requirements.txt pytest httpx && pytest
cd ms-cotizacion && pip install -r requirements-dev.txt && pytest
cd ms-perfilamiento && pip install -r requirements-dev.txt && pytest
```
