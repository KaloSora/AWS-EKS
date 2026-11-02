output "domain_nameservers" {
  description = "Set these nameservers in Namecheap Custom DNS"
  value       = aws_route53_zone.main.name_servers
}