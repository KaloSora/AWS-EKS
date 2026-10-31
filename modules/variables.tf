
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

variable "aws_account_id" {
  type        = string
  description = "AWS account ID"
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

variable "eks_kubernetes_version" {
  type        = string
  description = "Kubernetes version for the EKS cluster"
}

variable "eks_admin_principal_arn" {
  type        = string
  description = "ARN of the IAM principal with admin access to the EKS cluster"
}

variable "eks_public_access_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks allowed to access the EKS cluster API endpoint"
}

variable "eks_node_instance_types" {
  type        = list(string)
  description = "List of instance types for EKS worker nodes"
}

variable "eks_node_scaling" {
  description = "EKS managed node group scaling configuration"
  type = object({
    min_size     = number
    desired_size = number
    max_size     = number
  })
}

variable "vpc_endpoint_interface_services" {
  description = "Interface endpoint service suffixes to create in the private subnets"
  type        = set(string)
}
