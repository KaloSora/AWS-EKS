variable "name" {
  description = "Name prefix for endpoint resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC with DNS support and DNS hostnames enabled"
  type        = string
}

variable "private_subnets" {
  description = "Private subnets keyed by Availability Zone name; exactly one subnet per AZ"
  type = map(object({
    subnet_id      = string
    cidr_block     = string
    route_table_id = string
  }))

  validation {
    condition = length(var.private_subnets) > 0 && alltrue([
      for subnet in values(var.private_subnets) : can(cidrnetmask(subnet.cidr_block))
    ])
    error_message = "Provide at least one private subnet with a valid IPv4 CIDR, keyed by AZ name."
  }
}

variable "interface_services" {
  description = "AWS service suffixes for Interface endpoints; availability is checked in the provider region"
  type        = set(string)
  default = [
    "ssm",
    "ssmmessages",
    "ec2",
    "ebs",
    "elasticfilesystem",
    "logs",
    "monitoring",
    "ecr.api",
    "ecr.dkr",
    "sts",
    "eks",
    "eks-auth",
  ]

  validation {
    condition = alltrue([
      for service in var.interface_services :
      can(regex("^[a-z0-9][a-z0-9.-]*$", service)) && service != "s3"
    ])
    error_message = "Use service suffixes (for example ecr.api), or an empty set to disable Interface endpoints. S3 is managed separately as a Gateway endpoint."
  }
}

variable "enable_s3_gateway" {
  description = "Create the S3 Gateway endpoint required for private ECR image layer downloads"
  type        = bool
  default     = true
}

variable "endpoint_policies" {
  description = "Optional JSON endpoint policies keyed by service suffix, including s3; otherwise AWS default policies apply"
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for policy in values(var.endpoint_policies) : can(jsondecode(policy))])
    error_message = "Each endpoint policy must be valid JSON."
  }
}

variable "tags" {
  description = "Tags applied to endpoints and the shared security group"
  type        = map(string)
  default     = {}
}
