resource "kubernetes_namespace" "component" {
  count = local.karpenter_enabled ? 1 : 0

  metadata {
    name = nonsensitive(var.component.namespace)

    labels = {
      "pod-security.kubernetes.io/audit"         = "restricted"
      "pod-security.kubernetes.io/audit-version" = "v${var.k8s_version}"
      "pod-security.kubernetes.io/warn"          = "restricted"
      "pod-security.kubernetes.io/warn-version"  = "v${var.k8s_version}"
    }
  }
}

resource "helm_release" "component" {
  count = local.karpenter_enabled ? 1 : 0

  name             = var.component.release_name
  namespace        = kubernetes_namespace.component[0].metadata[0].name
  repository       = var.component.repository
  chart            = var.component.chart
  version          = var.component.version
  timeout          = var.component.timeout
  atomic           = var.component.atomic
  wait             = var.component.wait
  wait_for_jobs    = var.component.wait_for_jobs
  create_namespace = false

  values = [
    for name in var.component.value_templates :
    templatefile("${path.module}/helm_values/${name}", merge(var.component.config, {
      cluster_name            = var.cluster.name
      cluster_endpoint        = var.cluster.endpoint
      managed_node_group_name = var.cluster.managed_node_group_name
      controller_role_arn     = aws_iam_role.karpenter_controller[0].arn
      service_account_name    = local.karpenter_service_account
    }))
  ]

  depends_on = [
    aws_iam_role_policy.karpenter_controller,
    aws_eks_access_entry.karpenter_node,
  ]
}
