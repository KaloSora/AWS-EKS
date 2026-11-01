locals {
  csi_drivers = var.eks_csi_enabled ? {
    ebs = {
      addon_name      = "aws-ebs-csi-driver"
      service_account = "ebs-csi-controller-sa"
    }
    efs = {
      addon_name      = "aws-efs-csi-driver"
      service_account = "efs-csi-controller-sa"
    }
  } : {}

  oidc_issuer = aws_eks_cluster.this.identity[0].oidc[0].issuer
  oidc_host   = trimprefix(local.oidc_issuer, "https://")
}

resource "aws_iam_openid_connect_provider" "csi" {
  count = var.eks_csi_enabled ? 1 : 0

  url            = local.oidc_issuer
  client_id_list = ["sts.amazonaws.com"]
  tags           = var.tags
}

# Dedicated IRSA roles, restricted to each controller service account.
resource "aws_iam_role" "csi" {
  for_each = local.csi_drivers

  name_prefix = "eks-${each.key}-csi-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.csi[0].arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "system:serviceaccount:kube-system:${each.value.service_account}"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "csi" {
  for_each = local.csi_drivers

  # Keep attachments aligned with the enabled driver keys.

  role = aws_iam_role.csi[each.key].name
  policy_arn = join("", [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/",
    each.key == "ebs" ? "AmazonEBSCSIDriverPolicyV2" : "service-role/AmazonEFSCSIDriverPolicy"
  ])
}

resource "aws_eks_addon" "storage_csi" {
  for_each = local.csi_drivers

  cluster_name             = aws_eks_cluster.this.name
  addon_name               = each.value.addon_name
  addon_version            = var.csi_addon_versions[each.key]
  service_account_role_arn = aws_iam_role.csi[each.key].arn

  tags = var.tags

  depends_on = [
    aws_eks_node_group.this,
    aws_iam_role_policy_attachment.csi
  ]
}
