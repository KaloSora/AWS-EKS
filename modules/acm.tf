module "acm" {
  source = "./acm"

  hosted_zone_id            = module.route53.zone_id
  domain_name               = var.hosted_zone_name
  subject_alternative_names = var.acm_subject_alternative_names

  tags = {
    Environment = var.aws_env
    ManagedBy   = "Terraform"
  }
}
