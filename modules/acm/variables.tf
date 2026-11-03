variable "hosted_zone_id" {
  description = "Route 53 public hosted zone ID for DNS validation"
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.hosted_zone_id)) > 0
    error_message = "hosted_zone_id must be non-empty."
  }
}

variable "domain_name" {
  description = "Public hosted zone apex, supplied explicitly so validation record keys are known at plan time"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.domain_name)) && length(var.domain_name) <= 253
    error_message = "domain_name must be a lowercase DNS apex without a wildcard or trailing dot."
  }
}

variable "subject_alternative_names" {
  description = "Additional certificate names in this hosted zone, including optional wildcard names"
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for name in var.subject_alternative_names :
      can(regex("^(\\*\\.)?([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", name)) && length(name) <= 253
    ])
    error_message = "Additional names must be lowercase DNS names without trailing dots; a leading *. is allowed."
  }
}

variable "tags" {
  description = "Tags applied to the ACM certificate"
  type        = map(string)
  default     = {}
}
