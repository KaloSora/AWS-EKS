module "vpc" {
  source             = "./vpc"
  aws_env            = var.aws_env
  cidr_block         = var.cidr_block
  availability_zones = var.availability_zones
}
