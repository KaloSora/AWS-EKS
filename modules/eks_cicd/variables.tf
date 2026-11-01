variable "components" {
  description = "CI/CD component inventory rendered through the generic Helm component module"
  sensitive   = true

  type = map(object({
    enabled         = bool
    release_name    = string
    namespace       = string
    repository      = string
    chart           = string
    version         = string
    timeout         = number
    atomic          = bool
    wait            = bool
    wait_for_jobs   = bool
    value_templates = list(string)
    config          = map(string)
  }))

  validation {
    condition = alltrue([
      for name in keys(var.components) :
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", name))
    ])
    error_message = "Component keys must be valid lowercase Kubernetes-style names."
  }

  validation {
    condition = alltrue(flatten([
      for component in values(var.components) : [
        for template_name in component.value_templates :
        can(regex("^[A-Za-z0-9_.-]+\\.ya?ml$", template_name))
      ]
    ]))
    error_message = "value_templates entries must be YAML filenames located in helm_values."
  }

  validation {
    condition = length(distinct([
      for component in values(var.components) : component.namespace
      if component.enabled
      ])) == length([
      for component in values(var.components) : component.namespace
      if component.enabled
    ])
    error_message = "Enabled CI/CD components must use unique namespaces."
  }
}

variable "storage_class_name" {
  description = "Storage class name for persistent volumes"
  type        = string
}