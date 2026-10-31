output "interface_endpoint_ids" {
  description = "Interface endpoint IDs keyed by service suffix"
  value       = { for service, endpoint in aws_vpc_endpoint.interface : service => endpoint.id }
}

output "s3_gateway_endpoint_id" {
  description = "S3 Gateway endpoint ID, or null when disabled"
  value       = try(aws_vpc_endpoint.s3[0].id, null)
}

output "security_group_id" {
  description = "Shared Interface endpoint security group ID"
  value       = aws_security_group.this.id
}
