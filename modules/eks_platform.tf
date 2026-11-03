# module "eks_platform" {
#   source                 = "./eks_platform"
#   components             = var.eks_components
#   storage_class_name     = module.eks.storage_class_name
#   k8s_version            = var.eks_kubernetes_version

#   depends_on = [module.eks]
# }