variable "eks_argocd_ingress_enabled" {
  description = "Expose Argo CD through an HTTPS ALB restricted to eks_public_access_cidrs"
  type        = bool
  default     = false
  nullable    = false
}

variable "jenkins_ecr_role_arn" {
  description = "Optional existing IRSA role ARN to use in place of the Terraform-managed Jenkins role"
  type        = string
  default     = null
}

variable "jenkins_ecr_repository_name" {
  description = "Existing ECR repository in the EKS account and region that Jenkins can push to"
  type        = string
  default     = "aws-eks-app"
  nullable    = false
}

variable "gitops_github_token" {
  description = "GitHub token for the Jenkins GitOps credential"
  type        = string
  sensitive   = true
  default     = null
}

variable "gitops_github_username" {
  description = "GitHub username associated with the Jenkins GitOps token"
  type        = string
  default     = "KaloSora"
  nullable    = false
}

module "eks_cicd" {
  source = "./eks_cicd"

  components             = { for name, component in var.eks_components : name => component if name != "karpenter" }
  storage_class_name     = module.eks_storage.storage_class_names.ebs
  k8s_version            = var.eks_kubernetes_version
  jenkins_ecr_role_arn   = var.jenkins_ecr_role_arn
  gitops_github_token    = var.gitops_github_token
  gitops_github_username = var.gitops_github_username

  jenkins_ecr = {
    cluster_arn       = module.eks.cluster_arn
    oidc_provider_arn = module.eks.oidc_provider_arn
    repository_name   = var.jenkins_ecr_repository_name
  }

  public_ingress = var.eks_argocd_ingress_enabled ? {
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
