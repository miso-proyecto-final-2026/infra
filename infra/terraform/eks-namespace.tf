resource "kubernetes_namespace" "solventa_staging" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/part-of" = "solventa-experimentos"
      "environment"               = "staging"
    }
  }
}
