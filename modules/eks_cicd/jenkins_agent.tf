locals {
  jenkins_agent_enabled              = contains(local.enabled_component_names, "jenkins")
  jenkins_agent_namespace            = "cicd-build"
  jenkins_agent_service_account_name = "jenkins-ecr-publisher"
}

resource "kubernetes_namespace_v1" "jenkins_agent" {
  count = local.jenkins_agent_enabled ? 1 : 0

  metadata {
    name = local.jenkins_agent_namespace

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
    name        = local.jenkins_agent_service_account_name
    namespace   = kubernetes_namespace_v1.jenkins_agent[0].metadata[0].name
    annotations = local.jenkins_ecr_role_arn == null ? {} : { "eks.amazonaws.com/role-arn" = local.jenkins_ecr_role_arn }
  }

  automount_service_account_token = false

  depends_on = [aws_iam_role_policy.jenkins_ecr]
}
