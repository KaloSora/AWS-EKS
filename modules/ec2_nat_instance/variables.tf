variable "name" {
  description = "Name prefix for NAT resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC containing the NAT and client subnets"
  type        = string
}

variable "public_subnet_id" {
  description = "Subnet with a working default route to an Internet Gateway before instance launch"
  type        = string
}

variable "private_subnets" {
  description = "Client subnets keyed by AZ, with CIDRs and route tables to receive NAT default routes"
  type = map(object({
    cidr_block     = string
    route_table_id = string
  }))

  validation {
    condition = length(var.private_subnets) > 0 && alltrue([
      for subnet in values(var.private_subnets) : can(cidrnetmask(subnet.cidr_block))
    ])
    error_message = "Provide at least one private subnet with a valid IPv4 CIDR."
  }
}

variable "instance_type" {
  description = "NAT EC2 instance type; the module selects the matching AL2023 arm64 or x86_64 AMI"
  type        = string
  default     = "t4g.micro"
}

variable "ami_id" {
  description = "Optional pinned AL2023 AMI matching the instance architecture; null uses the current AWS public SSM parameter"
  type        = string
  default     = null
}

variable "allowed_tcp_ports" {
  description = "Destination TCP ports private clients may reach through NAT; HTTP/HTTPS by default"
  type        = set(number)
  default     = [80, 443]

  validation {
    condition = length(var.allowed_tcp_ports) > 0 && alltrue([
      for port in var.allowed_tcp_ports : floor(port) == port && port >= 1 && port <= 65535
    ])
    error_message = "Provide one or more integer TCP ports between 1 and 65535."
  }
}

variable "tags" {
  description = "Tags applied to NAT resources"
  type        = map(string)
  default     = {}
}
