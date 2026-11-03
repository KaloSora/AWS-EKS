variable "cluster_name" {
  description = "Existing standard EKS cluster name"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$", var.cluster_name))
    error_message = "cluster_name must be a valid EKS cluster name."
  }
}

variable "aws_region" {
  description = "AWS region of the cluster; must match the inherited AWS provider"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be an AWS region name."
  }
}

variable "vpc_id" {
  description = "VPC containing the EKS cluster and ALB target Pods"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^vpc-([0-9a-f]{8}|[0-9a-f]{17})$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID."
  }
}

variable "alb_controller_chart_version" {
  description = "Pinned chart version paired with the vendored v3.6.2 IAM policy; review both before upgrading"
  type        = string
  default     = "3.6.2"
  nullable    = false

  validation {
    condition     = var.alb_controller_chart_version == "3.6.2"
    error_message = "This module supports chart 3.6.2 only; upgrade its chart, IAM policy and validation together."
  }
}

variable "replica_count" {
  description = "Controller replicas; two provide leader-election failover when node capacity permits"
  type        = number
  default     = 2
  nullable    = false

  validation {
    condition     = var.replica_count >= 1 && var.replica_count == floor(var.replica_count)
    error_message = "replica_count must be a positive integer."
  }
}

variable "acm_certificate_arn" {
  description = "Optional issued ACM certificate enforced for all Ingresses using class alb; null preserves per-application certificate configuration"
  type        = string
  default     = null

  validation {
    condition = var.acm_certificate_arn == null ? true : can(regex(
      "^arn:aws:acm:[a-z0-9-]+:[0-9]{12}:certificate/[0-9a-f-]+$",
      var.acm_certificate_arn
    ))
    error_message = "acm_certificate_arn must be null or an ACM certificate ARN in the standard AWS partition."
  }
}

variable "tags" {
  description = "Tags for the Controller IAM role and policy"
  type        = map(string)
  default     = {}
  nullable    = false
}
