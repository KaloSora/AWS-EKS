module "eks_efs" {
  source = "./eks_efs"

  file_system_name = var.eks_efs_file_system_name
  throughput_mode  = var.eks_efs_throughput_mode
  vpc_id           = module.vpc.vpc_id
  private_subnet_ids_by_az = {
    for az in var.availability_zones : az => module.vpc.subnets_by_az[az].private_subnet_id
  }
  tags = {
    Environment = var.aws_env
    ManagedBy   = "Terraform"
  }
}

# Keep the cluster-specific rule outside eks_efs so cluster teardown can remove
# the EKS SG reference without destroying the file system or mount targets.
resource "aws_vpc_security_group_ingress_rule" "efs_from_nodes" {
  security_group_id            = module.eks_efs.mount_target_security_group_id
  referenced_security_group_id = module.eks.cluster_security_group_id
  description                  = "NFS from EKS managed nodes"
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049

  tags = {
    Environment = var.aws_env
    ManagedBy   = "Terraform"
  }
}
