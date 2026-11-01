locals {
  enabled_component_names = nonsensitive(toset([
    for name, component in var.components : name
    if component.enabled
  ]))
  jenkins_enabled                         = contains(local.enabled_component_names, "jenkins")
  jenkins_agent_namespace                 = "cicd-build"
  jenkins_agent_service_account_name      = "jenkins-agent"
  jenkins_controller_service_account_name = "jenkins-controller"
  k8s_pss_version                         = "v${join(".", slice(split(".", var.k8s_version), 0, 2))}"

  component_template_vars = {
    for name, component in var.components : name => merge(
      component.config,
      {
        storage_class = var.storage_class_name
      },
      name == "argocd" ? {
        argocd_admin_password_bcrypt = bcrypt(component.config["argocd_admin_password"])
      } : {},
      name == "jenkins" ? {
        jenkins_agent_namespace                 = local.jenkins_agent_namespace
        jenkins_agent_service_account_name      = local.jenkins_agent_service_account_name
        jenkins_controller_service_account_name = local.jenkins_controller_service_account_name
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