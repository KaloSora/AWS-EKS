variable "components" {
  description = "CI/CD component inventory rendered through Helm"
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

  validation {
    condition = alltrue([
      for component in values(var.components) :
      can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+([+-][0-9A-Za-z.-]+)?$", component.version)) &&
      component.timeout > 0 && component.timeout == floor(component.timeout)
    ])
    error_message = "Components must pin a chart version and use a positive integer timeout."
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

variable "jenkins_ecr_role_arn" {
  description = "Optional existing role override for the Jenkins ECR publisher service account"
  type        = string
  default     = null

  validation {
    condition     = var.jenkins_ecr_role_arn == null ? true : can(regex("^arn:aws(-[a-z0-9-]+)?:iam::[0-9]{12}:role/[^[:space:]]+$", var.jenkins_ecr_role_arn))
    error_message = "jenkins_ecr_role_arn must be an IAM role ARN or null."
  }
}

variable "jenkins_ecr" {
  description = "Cluster identity and target ECR repository for the managed Jenkins IRSA role"
  type = object({
    cluster_arn       = string
    oidc_provider_arn = string
    repository_name   = string
  })
  default = null

  validation {
    condition = var.jenkins_ecr == null ? true : (
      can(regex("^arn:aws(-[a-z0-9-]+)?:eks:[a-z0-9-]+:[0-9]{12}:cluster/[^/]+$", var.jenkins_ecr.cluster_arn)) &&
      (var.jenkins_ecr.oidc_provider_arn == null ? true : can(regex(
        "^arn:aws(-[a-z0-9-]+)?:iam::[0-9]{12}:oidc-provider/[^[:space:]]+$",
        var.jenkins_ecr.oidc_provider_arn
      )))
    )
    error_message = "jenkins_ecr requires an EKS cluster ARN and an IAM OIDC provider ARN when available."
  }

  validation {
    condition = var.jenkins_ecr == null ? true : try(
      length(var.jenkins_ecr.repository_name) >= 2 &&
      length(var.jenkins_ecr.repository_name) <= 256 &&
      can(regex("^[a-z0-9]+(([.]|_{1,2}|-+)[a-z0-9]+)*(/[a-z0-9]+(([.]|_{1,2}|-+)[a-z0-9]+)*)*$", var.jenkins_ecr.repository_name)),
      false
    )
    error_message = "jenkins_ecr.repository_name must be a valid lowercase private ECR repository name."
  }
}

variable "gitops_github_token" {
  description = "GitHub token for the Jenkins GitOps credential"
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.gitops_github_token == null ? true : can(regex("^[^[:space:]]+$", var.gitops_github_token))
    error_message = "gitops_github_token must be nonempty and contain no whitespace when set."
  }
}

variable "gitops_github_username" {
  description = "GitHub username associated with the Jenkins GitOps token"
  type        = string
  default     = "KaloSora"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$", var.gitops_github_username))
    error_message = "gitops_github_username must be a GitHub username."
  }
}

variable "public_ingress" {
  description = "Optional ALB and Route 53 settings for enabled public CI/CD components"
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
    condition = var.public_ingress == null ? true : (
      length(var.public_ingress.inbound_cidrs) > 0 && alltrue([
        for cidr in var.public_ingress.inbound_cidrs : try(cidrnetmask(cidr) != "0.0.0.0", false)
      ])
    )
    error_message = "Public CI/CD ALBs require at least one trusted IPv4 CIDR and cannot allow 0.0.0.0/0."
  }
}
