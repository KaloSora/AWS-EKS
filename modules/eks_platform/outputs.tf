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
