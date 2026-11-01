module "eks_cicd" {
  source                 = "./eks_cicd"
  components             = var.cicd_components
  storage_class_name     = module.eks.storage_class_name

  depends_on = [module.eks]
}