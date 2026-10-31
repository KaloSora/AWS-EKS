
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

  validation {
    condition = length(var.eks_node_instance_types) >= 1 && length(var.eks_node_instance_types) <= 20 && alltrue([
      for instance_type in var.eks_node_instance_types : can(regex("^[a-z0-9-]+[.][a-z0-9]+$", instance_type))
    ])
    error_message = "Provide 1 to 20 valid EC2 instance type names."
  }
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

variable "nat_instance_type" {
  description = "EC2 instance type for the shared NAT instance"
  type        = string
  default     = "t4g.micro"
}

variable "nat_instance_ami_id" {
  description = "Optional pinned AL2023 NAT AMI; null uses the current AWS public SSM parameter"
  type        = string
  default     = null
}

variable "eks_require_free_tier_eligible" {
  description = "Reject EKS instance types not labeled Free Tier eligible by AWS"
  type        = bool
  default     = true
}
