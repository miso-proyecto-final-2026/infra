# Repositorios ECR para las 3 imágenes del proyecto. El build/push real lo
# hace scripts/build-and-push.sh una vez creados (ver README).
locals {
  ecr_repositories = [
    "mock-open-finance",
    "ms-cotizacion",
    "ms-perfilamiento",
  ]
}

resource "aws_ecr_repository" "this" {
  for_each = toset(local.ecr_repositories)

  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true # permite destruir el repo aunque tenga imágenes (experimentos de corta vida)

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Mantener solo las últimas 10 imágenes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
