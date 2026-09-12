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

## Estructura

```
mock-open-finance/   Stub FastAPI de Open Finance con latencia inyectable
ms-cotizacion/        FastAPI + Redis + pybreaker + PostgreSQL + OTel (HA01)
ms-perfilamiento/     FastAPI + Redis + HPA + OTel (HA02)
k6/                   Scripts de carga y generador de datasets sintéticos
infra/terraform/      Namespace EKS, ElastiCache Redis, RDS PostgreSQL
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
COTIZACION_URL=http://localhost:8001 MOCK_URL=http://localhost:8000 \
  REDIS_URL=redis://localhost:6379/0 ./scripts/run-exp1.sh

# 4. Correr HA02 contra el stack local
PERFILAMIENTO_URL=http://localhost:8002 MOCK_URL=http://localhost:8000 \
  REDIS_URL=redis://localhost:6379/1 ./scripts/run-exp2.sh
```

`run-exp1.sh` y `run-exp2.sh` llaman `wait_for_pods_running`, que requiere
`kubectl` apuntando a un cluster; para correr contra `docker compose` sin
Kubernetes, exportar `NAMESPACE=` vacío o comentar esa línea si no hay
cluster disponible (ver `scripts/lib.sh`).

## Correr en EKS (staging)

```bash
# 1. Aprovisionar infraestructura (Terraform) + desplegar manifiestos K8s
export TF_VAR_db_password='...'
./scripts/setup.sh

# 2. Ejecutar los experimentos (vía port-forward o Ingress según el cluster)
./scripts/run-exp1.sh
./scripts/run-exp2.sh

# 3. Apagar todo al terminar (control de créditos AWS)
./scripts/teardown.sh
```

Configurar `infra/terraform/terraform.tfvars` a partir de
`terraform.tfvars.example` con los datos del cluster EKS existente (VPC,
subnets privadas, security group de los nodos).

## Tests unitarios

```bash
cd mock-open-finance && pip install -r requirements.txt pytest httpx && pytest
cd ms-cotizacion && pip install -r requirements-dev.txt && pytest
cd ms-perfilamiento && pip install -r requirements-dev.txt && pytest
```
