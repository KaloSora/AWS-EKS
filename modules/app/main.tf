locals {
  environment_names = toset([
    "dev",
    "uat",
    "preprod",
    "prod",
  ])
  k8s_pss_version = "v${var.k8s_version}"
}

resource "kubernetes_namespace" "environment" {
  for_each = local.environment_names

  metadata {
    name = each.value

    labels = {
      "app.kubernetes.io/managed-by"               = "Terraform"
      "ManagedBy"                                  = "Terraform"
      "environment"                                = each.value
      "pod-security.kubernetes.io/enforce"         = "restricted"
      "pod-security.kubernetes.io/enforce-version" = local.k8s_pss_version
      "pod-security.kubernetes.io/audit"           = "restricted"
      "pod-security.kubernetes.io/audit-version"   = local.k8s_pss_version
      "pod-security.kubernetes.io/warn"            = "restricted"
      "pod-security.kubernetes.io/warn-version"    = local.k8s_pss_version
    }
  }
}