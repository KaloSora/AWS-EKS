variable "cidr_block" {
  type        = string
  description = "IPv4 VPC CIDR (/16 to /20); public/private subnets add 8/4 prefix bits"

  validation {
    condition = can(cidrnetmask(var.cidr_block)) && try(
      tonumber(split("/", var.cidr_block)[1]) >= 16 &&
      tonumber(split("/", var.cidr_block)[1]) <= 20,
      false
    )
    error_message = "Use an IPv4 VPC CIDR with a /16 to /20 prefix so generated subnets fit AWS size limits."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "Exactly three distinct AZs; do not reorder after creating subnets"

  validation {
    condition = length(var.availability_zones) == 3 && length(distinct(var.availability_zones)) == 3 && alltrue([
      for az in var.availability_zones : length(trimspace(az)) > 0
    ])
    error_message = "Provide exactly three distinct, nonempty availability zone names."
  }
}

variable "aws_env" {
  type        = string
  description = "AWS environment name"
}
