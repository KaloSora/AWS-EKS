locals {
  jenkins_agent_enabled = contains(local.enabled_component_names, "jenkins")
}

resource "kubernetes_namespace_v1" "jenkins_agent" {
  count = local.jenkins_agent_enabled ? 1 : 0

  metadata {
    name = "cicd-build"

    # Kaniko runs as UID 0 with a limited capability set.
    labels = {
      "pod-security.kubernetes.io/audit"         = "restricted"
      "pod-security.kubernetes.io/audit-version" = local.k8s_pss_version
      "pod-security.kubernetes.io/warn"          = "restricted"
      "pod-security.kubernetes.io/warn-version"  = local.k8s_pss_version
    }
  }
}

resource "kubernetes_service_account_v1" "jenkins_agent" {
  count = local.jenkins_agent_enabled ? 1 : 0

  metadata {
    name        = "jenkins-ecr-publisher"
    namespace   = kubernetes_namespace_v1.jenkins_agent[0].metadata[0].name
    annotations = var.jenkins_ecr_role_arn == null ? {} : { "eks.amazonaws.com/role-arn" = var.jenkins_ecr_role_arn }
  }

  automount_service_account_token = false
}
