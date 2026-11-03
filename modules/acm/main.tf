data "aws_route53_zone" "this" {
  zone_id = var.hosted_zone_id
}

locals {
  domain_name = var.domain_name

  # Apex and wildcard names share an ACM validation record. Group them so
  # Terraform manages each CNAME once, including during certificate replacement.
  validation_records = {
    for record in aws_acm_certificate.this.domain_validation_options :
    trimprefix(record.domain_name, "*.") => record...
  }
}

resource "aws_acm_certificate" "this" {
  domain_name               = local.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  options {
    export = "DISABLED"
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = !data.aws_route53_zone.this.private_zone
      error_message = "ACM public certificates require a public hosted zone for DNS validation."
    }

    precondition {
      condition     = trimsuffix(data.aws_route53_zone.this.name, ".") == local.domain_name
      error_message = "domain_name must match the supplied hosted zone apex."
    }

    precondition {
      condition = alltrue([
        for name in var.subject_alternative_names :
        trimprefix(name, "*.") == local.domain_name || endswith(trimprefix(name, "*."), ".${local.domain_name}")
      ])
      error_message = "All additional certificate names must belong to the supplied hosted zone."
    }
  }
}

resource "aws_route53_record" "validation" {
  for_each = local.validation_records

  zone_id = var.hosted_zone_id
  name    = each.value[0].resource_record_name
  type    = each.value[0].resource_record_type
  ttl     = 60
  records = [each.value[0].resource_record_value]
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn = aws_acm_certificate.this.arn
  validation_record_fqdns = [
    for record in aws_route53_record.validation : record.fqdn
  ]

  timeouts {
    create = "45m"
  }
}
