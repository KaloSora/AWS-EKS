output "releases" {
  description = "Enabled platform Helm release names and namespaces; excludes credentials"
  value = {
    for name in local.enabled_component_names : name => {
      release_name = nonsensitive(var.components[name].release_name)
      namespace    = nonsensitive(var.components[name].namespace)
    }
  }
  depends_on = [helm_release.component]
}

output "argocd_url" {
  description = "HTTPS address published by the Argo CD Route 53 record"
  value       = local.argocd_ingress_enabled ? "https://${aws_route53_record.argocd[0].fqdn}" : null
}

output "karpenter_node_pool_manifest" {
  description = "Reviewable NodePool YAML using the EKS instance type allowlist"
  value       = local.karpenter_node_pool == null ? null : yamlencode(local.karpenter_node_pool)
}

output "karpenter_node_role_name" {
  description = "Terraform-managed node IAM role for EC2NodeClass.spec.role"
  value       = one(aws_iam_role.karpenter_node[*].name)
}
