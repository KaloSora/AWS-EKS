output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_id" {
  description = "Compatibility output: private subnet ID in the first configured AZ; use private_subnet_ids for EKS"
  value       = aws_subnet.private[var.availability_zones[0]].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs in availability_zones order"
  value       = [for az in var.availability_zones : aws_subnet.public[az].id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs in availability_zones order, for EKS node groups and cluster networking"
  value       = [for az in var.availability_zones : aws_subnet.private[az].id]
}

output "subnets_by_az" {
  description = "Public and private subnet IDs and CIDRs indexed by AZ"
  value = {
    for az, subnet in local.subnets : az => {
      public_subnet_id  = aws_subnet.public[az].id
      private_subnet_id = aws_subnet.private[az].id
      public_cidr       = subnet.public_cidr
      private_cidr      = subnet.private_cidr
    }
  }
}
