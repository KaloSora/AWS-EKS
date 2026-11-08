module "app" {
  source      = "./app"
  k8s_version = var.eks_kubernetes_version

  depends_on = [module.eks]
}