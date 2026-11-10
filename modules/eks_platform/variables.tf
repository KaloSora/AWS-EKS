variable "components" {
  description = "Platform component inventory rendered through the generic Helm component module"
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
    error_message = "Enabled platform components must use unique namespaces."
  }

  validation {
    condition = alltrue([
      for component in values(var.components) :
      can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+([+-][0-9A-Za-z.-]+)?$", component.version)) &&
      component.timeout > 0 && component.timeout == floor(component.timeout)
    ])
    error_message = "Components must pin a chart version and use a positive integer timeout."
  }

  validation {
    condition = try(var.components["karpenter"].enabled, false) ? try(
      var.components["karpenter"].version == "1.15.1" &&
      can(regex("^[1-9][0-9]*$", var.components["karpenter"].config["replicas"])) &&
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.components["karpenter"].config["ec2_node_class_name"])),
      false
    ) : true
    error_message = "Enabled Karpenter requires chart 1.15.1, which matches the bundled IAM policy, positive integer replicas and a valid ec2_node_class_name."
  }

  validation {
    condition = try(var.components["karpenter"].enabled, false) ? (
      contains(["true", "false"], try(var.components["karpenter"].config["provisioning_enabled"], "false")) &&
      (try(var.components["karpenter"].config["provisioning_enabled"], "false") == "true" ? try(
        can(regex("^al2023@v[0-9]{8}$", var.components["karpenter"].config["ami_alias"])) &&
        can(regex("^[1-9][0-9]*$", var.components["karpenter"].config["node_pool_cpu_limit"])),
        false
      ) : true)
    ) : true
    error_message = "Karpenter provisioning_enabled must be true or false. Enabled provisioning requires a pinned al2023@vYYYYMMDD ami_alias and a positive integer node_pool_cpu_limit."
  }
}

variable "karpenter_cluster" {
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
    condition     = var.karpenter_cluster == null ? true : length(var.karpenter_cluster.instance_types) > 0
    error_message = "Karpenter requires at least one explicitly allowed instance type."
  }
}

variable "storage_class_name" {
  description = "Storage class name for persistent volumes"
  type        = string
}

variable "k8s_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}

variable "argocd_ingress" {
  description = "Optional ALB and Route 53 settings for the enabled Argo CD component"
  type = object({
    ingress_class    = string
    certificate_arn  = string
    hosted_zone_id   = string
    hosted_zone_name = string
    alb_name         = string
    inbound_cidrs    = list(string)
  })
  default = null

  validation {
    condition = var.argocd_ingress == null ? true : (
      length(var.argocd_ingress.inbound_cidrs) > 0 && alltrue([
        for cidr in var.argocd_ingress.inbound_cidrs : try(cidrnetmask(cidr) != "0.0.0.0", false)
      ])
    )
    error_message = "An Argo CD ALB requires at least one trusted IPv4 CIDR and cannot allow 0.0.0.0/0."
  }
}
