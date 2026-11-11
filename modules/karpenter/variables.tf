variable "component" {
  description = "Karpenter Helm release settings from the component inventory"
  sensitive   = true
  default     = null

  type = object({
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
  })

  validation {
    condition = var.component == null ? true : (
      var.component.timeout > 0 && var.component.timeout == floor(var.component.timeout) &&
      alltrue([for name in var.component.value_templates : can(regex("^[A-Za-z0-9_.-]+\\.ya?ml$", name))])
    )
    error_message = "Karpenter requires a positive integer timeout and Helm values template filenames."
  }

  validation {
    condition = try(var.component.enabled, false) ? try(
      var.component.version == "1.15.1" &&
      can(regex("^[1-9][0-9]*$", var.component.config["replicas"])) &&
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.component.config["ec2_node_class_name"])),
      false
    ) : true
    error_message = "Enabled Karpenter requires chart 1.15.1, which matches the bundled IAM policy, positive integer replicas and a valid ec2_node_class_name."
  }

  validation {
    condition = try(var.component.enabled, false) ? (
      contains(["true", "false"], try(var.component.config["provisioning_enabled"], "false")) &&
      (try(var.component.config["provisioning_enabled"], "false") == "true" ? try(
        can(regex("^al2023@v[0-9]{8}$", var.component.config["ami_alias"])) &&
        can(regex("^[1-9][0-9]*$", var.component.config["node_pool_cpu_limit"])),
        false
      ) : true)
    ) : true
    error_message = "Karpenter provisioning_enabled must be true or false. Enabled provisioning requires a pinned al2023@vYYYYMMDD ami_alias and a positive integer node_pool_cpu_limit."
  }
}

variable "cluster" {
  description = "Existing cluster and exact instance type allowlist used by Karpenter"
  type = object({
    name                    = string
    arn                     = string
    oidc_provider_arn       = string
    endpoint                = string
    managed_node_group_name = string
    instance_types          = list(string)
    private_subnet_ids      = optional(list(string), [])
    node_security_group_id  = optional(string)
  })
  default = null

  validation {
    condition     = var.cluster == null ? true : length(var.cluster.instance_types) > 0
    error_message = "Karpenter requires at least one explicitly allowed instance type."
  }
}

variable "k8s_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}
