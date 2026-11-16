locals {
  enabled_component_names = nonsensitive(toset([
    for name, component in var.components : name
    if component.enabled
  ]))
  k8s_pss_version = "v${var.k8s_version}"

  component_template_vars = {
    for name, component in var.components : name => merge(
      component.config,
      {
        storage_class = var.storage_class_name
      },
      name == "jenkins" && local.jenkins_agent_enabled ? {
        jenkins_agent_namespace       = kubernetes_service_account_v1.jenkins_agent[0].metadata[0].namespace
        jenkins_agent_service_account = kubernetes_service_account_v1.jenkins_agent[0].metadata[0].name
        jenkins_agent_pod_yaml        = file("${path.module}/pod_templates/aws-eks-app.yaml")
        jenkins_gitops_secret_name    = one(kubernetes_secret_v1.jenkins_gitops[*].metadata[0].name)
        jenkins_gitops_revision       = one(terraform_data.jenkins_gitops_revision[*].id)
        jenkins_gitops_init_script    = file("${path.module}/jenkins_init/gitops-credential.groovy")
      } : {}
    )
  }

  rendered_component_values = {
    for name, component in var.components : name => [
      for template_name in component.value_templates :
      templatefile(
        "${path.module}/helm_values/${template_name}",
        local.component_template_vars[name]
      )
    ] if contains(local.enabled_component_names, name)
  }
}

# One namespace is created for every enabled component in the inventory.
resource "kubernetes_namespace" "component" {
  for_each = local.enabled_component_names

  metadata {
    name = nonsensitive(var.components[each.key].namespace)

    labels = {
      "pod-security.kubernetes.io/audit"         = "restricted"
      "pod-security.kubernetes.io/audit-version" = local.k8s_pss_version
      "pod-security.kubernetes.io/warn"          = "restricted"
      "pod-security.kubernetes.io/warn-version"  = local.k8s_pss_version
    }
  }
}

# Terraform owns the namespaces; Helm manages the CI/CD releases.
resource "helm_release" "component" {
  for_each = local.enabled_component_names

  name             = var.components[each.key].release_name
  namespace        = kubernetes_namespace.component[each.key].metadata[0].name
  repository       = var.components[each.key].repository
  chart            = var.components[each.key].chart
  version          = var.components[each.key].version
  timeout          = var.components[each.key].timeout
  atomic           = var.components[each.key].atomic
  wait             = var.components[each.key].wait
  wait_for_jobs    = var.components[each.key].wait_for_jobs
  create_namespace = false
  values           = local.rendered_component_values[each.key]
}
