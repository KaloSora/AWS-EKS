output "eks_platform_releases" {
  description = "Enabled platform releases and namespaces"
  value       = merge(module.eks_cicd.releases, module.karpenter.releases)
}

output "argocd_url" {
  description = "Public Argo CD HTTPS URL when its Ingress is enabled"
  value       = module.eks_cicd.argocd_url
}

output "karpenter_node_pool_manifest" {
  description = "Reviewable Karpenter NodePool YAML"
  value       = module.karpenter.karpenter_node_pool_manifest
}

output "karpenter_node_role_name" {
  description = "Terraform-managed node IAM role for EC2NodeClass.spec.role"
  value       = module.karpenter.karpenter_node_role_name
}
