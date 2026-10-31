module "ec2_nat_instance" {
  source = "./ec2_nat_instance"

  name             = var.aws_env
  vpc_id           = module.vpc.vpc_id
  public_subnet_id = module.vpc.public_subnet_ids[0]
  private_subnets = {
    for az, subnet in module.vpc.subnets_by_az : az => {
      cidr_block     = subnet.private_cidr
      route_table_id = module.vpc.private_route_table_ids[az]
    }
  }

  instance_type = var.nat_instance_type
  ami_id        = var.nat_instance_ami_id

  tags = {
    Environment = var.aws_env
    ManagedBy   = "Terraform"
  }

  # Ensure the IGW, public route and subnet associations exist before boot.
  depends_on = [module.vpc]
}

output "nat_instance_id" {
  description = "NAT instance ID for SSM diagnostics"
  value       = module.ec2_nat_instance.instance_id
}

output "nat_public_ip" {
  description = "Public egress IP shared by private nodes"
  value       = module.ec2_nat_instance.public_ip
}
