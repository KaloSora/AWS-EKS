variable "file_system_name" {
  description = "EFS Name tag; changing the name does not change the file system identity"
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.file_system_name)) > 0 && length(var.file_system_name) <= 256
    error_message = "file_system_name must be non-empty and at most 256 characters."
  }
}

variable "vpc_id" {
  description = "VPC containing the private EFS mount targets"
  type        = string
  nullable    = false
}

variable "private_subnet_ids_by_az" {
  description = "Private subnet IDs keyed by AZ; supply one subnet per AZ used by nodes"
  type        = map(string)
  nullable    = false

  validation {
    condition     = length(var.private_subnet_ids_by_az) > 0 && length(distinct(values(var.private_subnet_ids_by_az))) == length(var.private_subnet_ids_by_az)
    error_message = "Supply at least one mount-target subnet and do not repeat subnet IDs."
  }
}

variable "throughput_mode" {
  description = "Bursting has storage-based throughput and burst credits; elastic bills for I/O"
  type        = string
  default     = "bursting"
  nullable    = false

  validation {
    condition     = contains(["bursting", "elastic"], var.throughput_mode)
    error_message = "throughput_mode must be bursting or elastic."
  }
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
