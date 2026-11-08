variable "k8s_version" {
  type        = string
  description = "Kubernetes version used to pin Pod Security Admission policy versions"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+(?:\\.[0-9]+)?$", var.k8s_version))
    error_message = "k8s_version must be a semantic Kubernetes version such as 1.28.8 or v1.28.8."
  }
}