variable "efs_file_system_id" {
  description = "Existing EFS file system used for dynamic access-point provisioning"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^fs-([0-9a-f]{8}|[0-9a-f]{17})$", var.efs_file_system_id))
    error_message = "efs_file_system_id must be an EFS ID such as fs-0123456789abcdef0."
  }
}

variable "ebs_storage_class_name" {
  description = "Name of the non-default EBS gp3 StorageClass"
  type        = string
  default     = "ebs-sc"
  nullable    = false

  validation {
    condition     = length(var.ebs_storage_class_name) <= 63 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ebs_storage_class_name))
    error_message = "Use a lowercase DNS label of at most 63 characters."
  }
}

variable "efs_storage_class_name" {
  description = "Name of the non-default EFS access-point StorageClass"
  type        = string
  default     = "efs-sc"
  nullable    = false

  validation {
    condition     = length(var.efs_storage_class_name) <= 63 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.efs_storage_class_name))
    error_message = "Use a lowercase DNS label of at most 63 characters."
  }
}

variable "reclaim_policy" {
  description = "PV reclaim policy; Retain requires deliberate cleanup after PVC deletion"
  type        = string
  default     = "Retain"
  nullable    = false

  validation {
    condition     = contains(["Retain", "Delete"], var.reclaim_policy)
    error_message = "reclaim_policy must be Retain or Delete."
  }
}
