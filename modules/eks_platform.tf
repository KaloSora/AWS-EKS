variable "eks_argocd_ingress_enabled" {
  description = "Expose Argo CD through an HTTPS ALB restricted to eks_public_access_cidrs"
  type        = bool
  default     = false
  nullable    = false
}

module "eks_platform" {
  source = "./eks_platform"

  components         = var.eks_components
  storage_class_name = module.eks_storage.storage_class_names.ebs
  k8s_version        = var.eks_kubernetes_version

  karpenter_cluster = {
    name                    = module.eks.cluster_name
    arn                     = module.eks.cluster_arn
    oidc_provider_arn       = module.eks.oidc_provider_arn
    endpoint                = module.eks.cluster_endpoint
    managed_node_group_name = module.eks.node_group_name
    instance_types          = var.eks_node_instance_types
    private_subnet_ids      = module.vpc.private_subnet_ids
    node_security_group_id  = module.eks.cluster_security_group_id
  }

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
