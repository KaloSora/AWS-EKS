module "karpenter" {
  source = "./karpenter"

  component   = try(var.eks_components["karpenter"], null)
  k8s_version = var.eks_kubernetes_version

  cluster = {
    name                    = module.eks.cluster_name
    arn                     = module.eks.cluster_arn
    oidc_provider_arn       = module.eks.oidc_provider_arn
    endpoint                = module.eks.cluster_endpoint
    managed_node_group_name = module.eks.node_group_name
    instance_types          = var.eks_node_instance_types
    private_subnet_ids      = module.vpc.private_subnet_ids
    node_security_group_id  = module.eks.cluster_security_group_id
  }

  # The controller and cleanup job run on the existing managed node group.
  depends_on = [module.eks]
}
