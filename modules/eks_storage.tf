module "eks_storage" {
  source = "./eks_storage"

  providers = {
    helm = helm
  }

  efs_file_system_id = module.eks_efs.file_system_id
  reclaim_policy     = "Delete"

  depends_on = [module.eks, aws_vpc_security_group_ingress_rule.efs_from_nodes]
}
