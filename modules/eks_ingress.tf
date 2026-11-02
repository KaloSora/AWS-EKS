module "eks_ingress" {
  source = "./eks_ingress"

  cluster_name                 = module.eks.cluster_name
  aws_region                   = var.aws_region
  vpc_id                       = module.vpc.vpc_id
  alb_controller_chart_version = var.eks_ingress_chart_version
  replica_count                = var.eks_ingress_replica_count

  tags = {
    Environment = var.aws_env
    ManagedBy   = "Terraform"
  }

  # The existing cluster OIDC provider and managed nodes must precede the
  # Controller lookups/install. Generate kubeconfig before this deployment stage.
  depends_on = [module.eks]
}
