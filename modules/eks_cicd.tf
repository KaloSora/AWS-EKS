variable "eks_argocd_ingress_enabled" {
  description = "Expose Argo CD through an HTTPS ALB restricted to eks_public_access_cidrs"
  type        = bool
  default     = false
  nullable    = false
}

module "eks_cicd" {
  source = "./eks_cicd"

  components         = { for name, component in var.eks_components : name => component if name != "karpenter" }
  storage_class_name = module.eks_storage.storage_class_names.ebs
  k8s_version        = var.eks_kubernetes_version

  argocd_ingress = var.eks_argocd_ingress_enabled ? {
    ingress_class    = module.eks_ingress.ingress_class_name
    certificate_arn  = module.acm.certificate_arn
    hosted_zone_id   = module.route53.zone_id
    hosted_zone_name = var.hosted_zone_name
    alb_name         = "argocd-${substr(sha256("${var.aws_env}-eks"), 0, 12)}"
    inbound_cidrs    = var.eks_public_access_cidrs
  } : null

  # Generate the local kubeconfig before applying this Kubernetes/Helm stage.
  depends_on = [module.eks]
}
