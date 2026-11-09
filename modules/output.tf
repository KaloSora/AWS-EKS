output "eks_platform_releases" {
  description = "Enabled platform releases and namespaces"
  value       = module.eks_platform.releases
}

output "argocd_url" {
  description = "Public Argo CD HTTPS URL when its Ingress is enabled"
  value       = module.eks_platform.argocd_url
}
