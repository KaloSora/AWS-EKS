output "releases" {
  description = "Enabled Karpenter controller Helm release and namespace"
  value = local.karpenter_enabled ? {
    karpenter = {
      release_name = nonsensitive(var.component.release_name)
      namespace    = nonsensitive(var.component.namespace)
    }
  } : {}
  depends_on = [helm_release.component]
}

output "karpenter_node_pool_manifest" {
  description = "Reviewable NodePool YAML using the EKS instance type allowlist"
  value       = local.karpenter_node_pool == null ? null : yamlencode(local.karpenter_node_pool)
}

output "karpenter_node_role_name" {
  description = "Terraform-managed node IAM role for EC2NodeClass.spec.role"
  value       = one(aws_iam_role.karpenter_node[*].name)
}
