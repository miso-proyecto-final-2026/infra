#!/usr/bin/env bash
# Construye y publica las 3 imágenes a los repositorios ECR creados por
# Terraform. Debe correr después de `terraform apply` (infra/terraform).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

: "${IMAGE_TAG:=latest}"

# Arquitectura de los nodos del cluster, NO la de la máquina que construye.
# El node group usa t3.medium (x86_64), así que las imágenes deben ser
# linux/amd64. En un Mac con Apple Silicon, `docker build` a secas produce
# arm64 y los pods fallan con:
#   "no match for platform in manifest: not found"  -> ImagePullBackOff
# Si algún día se cambia el node group a instancias Graviton (t4g.*),
# exportar TARGET_PLATFORM=linux/arm64 antes de correr este script.
: "${TARGET_PLATFORM:=linux/amd64}"

command -v aws > /dev/null 2>&1 || { err "aws CLI no está instalado."; exit 1; }
command -v docker > /dev/null 2>&1 || { err "docker no está instalado."; exit 1; }

pushd infra/terraform > /dev/null
AWS_REGION=$(terraform output -raw aws_region)
ECR_URLS_JSON=$(terraform output -json ecr_repository_urls)
popd > /dev/null

registry=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(list(d.values())[0].split('/')[0])" "${ECR_URLS_JSON}")

log "Autenticando Docker contra ECR (${registry})..."
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${registry}"

for dir in mock-open-finance ms-cotizacion ms-perfilamiento; do
  repo_url=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['${dir}'])" "${ECR_URLS_JSON}")
  log "Build ${dir} -> ${repo_url}:${IMAGE_TAG} (${TARGET_PLATFORM})"
  # buildx con --push: construye para la plataforma destino y publica en un
  # solo paso. Con `docker build` normal, --platform en una máquina arm64
  # deja la imagen en el store local sin el manifiesto correcto.
  docker buildx build \
    --platform "${TARGET_PLATFORM}" \
    -t "${repo_url}:${IMAGE_TAG}" \
    --push \
    "./${dir}"
done

log "Imágenes publicadas. Corre 'terraform output ecr_repository_urls' para verlas."
