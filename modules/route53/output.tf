output "zone_id" {
  description = "Route 53 public hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "domain_nameservers" {
  description = "Set these nameservers in Namecheap Custom DNS"
  value       = aws_route53_zone.main.name_servers
}
