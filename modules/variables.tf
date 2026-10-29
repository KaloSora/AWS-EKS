
variable "budget_email" {
  description = "budget alert email address"
  type        = string
}

variable "budget_start" {
  description = "budget start time, UTC, format YYYY-MM-DD_HH:mm"
  type        = string
}

variable "budget_end" {
  description = "budget end time, UTC, format YYYY-MM-DD_HH:mm"
  type        = string
}

variable "budget_amount" {
  description = "budget amount"
  type        = number
}

variable "budget_unit" {
  description = "budget unit"
  type        = string
}

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
