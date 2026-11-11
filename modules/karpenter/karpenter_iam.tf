locals {
  karpenter_enabled         = try(nonsensitive(var.component.enabled), false)
  karpenter_service_account = "karpenter"
  karpenter_cluster_arn     = try(split(":", var.cluster.arn), [])
  karpenter_oidc_arn        = try(var.cluster.oidc_provider_arn, null)
  karpenter_oidc_host       = try(split(":oidc-provider/", local.karpenter_oidc_arn)[1], "")
}

data "aws_partition" "karpenter" {
  count = local.karpenter_enabled ? 1 : 0
}

resource "aws_iam_role" "karpenter_controller" {
  count       = local.karpenter_enabled ? 1 : 0
  name_prefix = "eks-karpenter-controller-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = local.karpenter_oidc_arn }
      Condition = {
        StringEquals = {
          "${local.karpenter_oidc_host}:aud" = "sts.amazonaws.com"
          "${local.karpenter_oidc_host}:sub" = "system:serviceaccount:${nonsensitive(var.component.namespace)}:${local.karpenter_service_account}"
        }
      }
    }]
  })

  lifecycle {
    precondition {
      condition     = local.karpenter_oidc_host != ""
      error_message = "Karpenter requires the cluster IAM OIDC provider. In the root, enable eks_csi_enabled to provision it."
    }
  }
}

resource "aws_iam_role" "karpenter_node" {
  count       = local.karpenter_enabled ? 1 : 0
  name_prefix = "eks-karpenter-node-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.${data.aws_partition.karpenter[0].dns_suffix}" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_node" {
  for_each = local.karpenter_enabled ? toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEC2ContainerRegistryPullOnly",
    "AmazonEKS_CNI_Policy",
  ]) : toset([])

  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = "arn:${data.aws_partition.karpenter[0].partition}:iam::aws:policy/${each.key}"
}

resource "aws_eks_access_entry" "karpenter_node" {
  count         = local.karpenter_enabled ? 1 : 0
  cluster_name  = var.cluster.name
  principal_arn = aws_iam_role.karpenter_node[0].arn
  type          = "EC2_LINUX"

  depends_on = [aws_iam_role_policy_attachment.karpenter_node]
}

resource "aws_iam_role_policy" "karpenter_controller" {
  count = local.karpenter_enabled ? 1 : 0
  name  = "karpenter-controller-v1-15-1"
  role  = aws_iam_role.karpenter_controller[0].name

  # Based on the v1.15.1 upstream CloudFormation controller policies.
  # The chart leaves interruption handling and Zonal Shift disabled.
  policy = templatefile("${path.module}/policies/karpenter-controller-v1.15.1.json.tftpl", {
    partition     = local.karpenter_cluster_arn[1]
    region        = local.karpenter_cluster_arn[3]
    account_id    = local.karpenter_cluster_arn[4]
    cluster_name  = var.cluster.name
    node_role_arn = aws_iam_role.karpenter_node[0].arn
  })
}
