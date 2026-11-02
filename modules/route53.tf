module "route53" {
  source = "./route53"
  domain_name = var.hosted_zone_name
}