module "eks" {
  source = "./eks"

  cluster_name       = "${var.aws_env}-eks"
  kubernetes_version = var.eks_kubernetes_version
  private_subnet_ids = module.vpc.private_subnet_ids

  admin_principal_arn = var.eks_admin_principal_arn

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.eks_public_access_cidrs

  instance_types             = var.eks_node_instance_types
  require_free_tier_eligible = var.eks_require_free_tier_eligible
  capacity_type              = "ON_DEMAND"
  node_scaling               = var.eks_node_scaling
  tags = {
    Environment = var.aws_env
    ManagedBy   = "Terraform"
  }

  # Private nodes use NAT for AWS APIs/internet and the Gateway endpoint for S3.
  depends_on = [terraform_data.eks_preflight, module.ec2_nat_instance]
}
