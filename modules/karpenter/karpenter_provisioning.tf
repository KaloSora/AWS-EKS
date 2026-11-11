locals {
  karpenter_config               = try(nonsensitive(var.component.config), {})
  karpenter_provisioning_enabled = local.karpenter_enabled && try(local.karpenter_config["provisioning_enabled"], "false") == "true"
  karpenter_node_pool = local.karpenter_enabled && var.cluster != null ? {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "general" }
    spec = merge(
      {
        template = {
          spec = {
            nodeClassRef = {
              group = "karpenter.k8s.aws"
              kind  = "EC2NodeClass"
              name  = local.karpenter_config["ec2_node_class_name"]
            }
            requirements = [
              { key = "node.kubernetes.io/instance-type", operator = "In", values = distinct(var.cluster.instance_types) },
              { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
              { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand"] }
            ]
          }
        }
      },
      local.karpenter_provisioning_enabled ? {
        limits = { cpu = local.karpenter_config["node_pool_cpu_limit"] }
      } : {}
    )
  } : null
}

# A separate Helm release can be planned before the controller chart installs
# its CRDs. It also supplies a blocking pre-delete hook for dynamic nodes.
resource "helm_release" "karpenter_provisioning" {
  count = local.karpenter_provisioning_enabled ? 1 : 0

  name      = "karpenter-provisioning"
  namespace = helm_release.component[0].namespace
  chart     = "${path.module}/charts/karpenter-provisioning"
  wait      = true
  timeout   = 1200

  values = [yamlencode({
    nodePool             = local.karpenter_node_pool
    managedNodeGroupName = var.cluster.managed_node_group_name
    nodeClass = {
      apiVersion = "karpenter.k8s.aws/v1"
      kind       = "EC2NodeClass"
      metadata   = { name = local.karpenter_config["ec2_node_class_name"] }
      spec = {
        role                       = aws_iam_role.karpenter_node[0].name
        amiSelectorTerms           = [{ alias = local.karpenter_config["ami_alias"] }]
        subnetSelectorTerms        = [for id in var.cluster.private_subnet_ids : { id = id }]
        securityGroupSelectorTerms = [{ id = var.cluster.node_security_group_id }]
        associatePublicIPAddress   = false
      }
    }
  })]

  lifecycle {
    precondition {
      condition     = try(length(var.cluster.private_subnet_ids) > 0 && var.cluster.node_security_group_id != null, false)
      error_message = "Karpenter provisioning requires private subnet IDs and a node security group."
    }
  }
}
