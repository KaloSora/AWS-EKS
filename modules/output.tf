output "eks_efs_file_system_id" {
  description = "EFS file system passed to the EFS StorageClass"
  value       = module.eks_efs.file_system_id
}

output "nat_instance_id" {
  description = "NAT instance ID for SSM diagnostics"
  value       = var.nat_instance_enable ? module.ec2_nat_instance[0].instance_id : null
}

output "nat_public_ip" {
  description = "Public egress IP shared by private nodes"
  value       = var.nat_instance_enable ? module.ec2_nat_instance[0].public_ip : null
}
