module "vpc_endpoint" {
  source = "./vpc_endpoint"

  name   = var.aws_env
  vpc_id = module.vpc.vpc_id
  private_subnets = {
    for az, subnet in module.vpc.subnets_by_az : az => {
      subnet_id      = subnet.private_subnet_id
      cidr_block     = subnet.private_cidr
      route_table_id = module.vpc.private_route_table_ids[az]
    }
  }

  interface_services = var.vpc_endpoint_interface_services
  enable_s3_gateway  = true

  tags = {
    Environment = var.aws_env
    ManagedBy   = "Terraform"
  }
}
