output "instance_id" {
  description = "NAT instance ID for SSM management and health checks"
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "Stable public egress IPv4 address"
  value       = aws_eip.this.public_ip
}

output "network_interface_id" {
  description = "Stable NAT ENI targeted by private default routes"
  value       = aws_network_interface.this.id
}

output "security_group_id" {
  description = "NAT security group ID"
  value       = aws_security_group.this.id
}
