variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version supported in the target region, for example 1.35"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets in at least two AZs, with NAT or the required VPC endpoints"
  type        = list(string)

  validation {
    condition     = length(distinct(var.private_subnet_ids)) >= 2
    error_message = "Provide at least two distinct private subnet IDs in different AZs."
  }
}

variable "admin_principal_arn" {
  description = "IAM role or user ARN granted cluster administrator access; do not use an STS session ARN"
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:(role|user)/.+$", var.admin_principal_arn))
    error_message = "Use a persistent IAM role or user ARN."
  }
}

variable "endpoint_public_access" {
  description = "Enable public API access in addition to the always-enabled private endpoint"
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = "Allowed public API IPv4 CIDRs; required when public access is enabled"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.endpoint_public_access_cidrs : can(cidrnetmask(cidr)) && cidr != "0.0.0.0/0"])
    error_message = "Use IPv4 CIDRs limited to trusted networks; 0.0.0.0/0 is not allowed."
  }
}

variable "instance_types" {
  description = "x86_64 instance types compatible with the AL2023 node AMI"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "capacity_type" {
  description = "Managed node group purchasing option"
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "Use ON_DEMAND or SPOT."
  }
}

variable "node_scaling" {
  description = "Managed node group minimum, initial desired and maximum node counts"
  type = object({
    min_size     = number
    desired_size = number
    max_size     = number
  })
  default = {
    min_size     = 1
    desired_size = 2
    max_size     = 3
  }

  validation {
    condition = (
      var.node_scaling.min_size >= 0 &&
      var.node_scaling.max_size >= 1 &&
      var.node_scaling.min_size <= var.node_scaling.desired_size &&
      var.node_scaling.desired_size <= var.node_scaling.max_size &&
      alltrue([for size in values(var.node_scaling) : floor(size) == size])
    )
    error_message = "Use integer counts with 0 <= min_size <= desired_size <= max_size and max_size >= 1."
  }
}

variable "tags" {
  description = "Tags for module resources"
  type        = map(string)
  default     = {}
}
