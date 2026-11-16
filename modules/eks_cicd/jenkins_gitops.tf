resource "kubernetes_secret_v1" "jenkins_gitops" {
  count = contains(local.enabled_component_names, "jenkins") && nonsensitive(var.gitops_github_token != null) ? 1 : 0

  metadata {
    name      = "jenkins-gitops"
    namespace = kubernetes_namespace.component["jenkins"].metadata[0].name
  }

  type = "Opaque"
  data = {
    username = var.gitops_github_username
    token    = var.gitops_github_token
  }
}

# Give Helm a new, non-secret rollout marker whenever credential data changes.
resource "terraform_data" "jenkins_gitops_revision" {
  count = length(kubernetes_secret_v1.jenkins_gitops)

  lifecycle {
    replace_triggered_by = [kubernetes_secret_v1.jenkins_gitops[count.index].data]
  }
}
