output "namespace_names" {
  description = "Application environment namespace names"
  value       = local.environment_names
  depends_on  = [kubernetes_namespace.environment]
}