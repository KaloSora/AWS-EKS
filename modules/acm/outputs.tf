output "certificate_arn" {
  description = "Issued ACM certificate ARN for the ALB Ingress certificate-arn annotation"
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "domain_name" {
  description = "Primary certificate domain from the public hosted zone"
  value       = aws_acm_certificate.this.domain_name
}
