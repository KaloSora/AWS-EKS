
variable "aws_region" {
  type        = string
  description = "AWS provider region for managed resources; backend region is configured separately"
}

variable "aws_env" {
  type        = string
  description = "AWS environment name"
}

variable "cidr_block" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  description = "Three distinct AZs, in stable order; each receives public and private subnets"
}
