# Resolve the existing cluster and its IAM OIDC provider. This module does not
# create a second provider for an issuer already managed by the EKS/CSI module.
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

locals {
  oidc_host            = trimprefix(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://")
  service_account_name = "aws-load-balancer-controller"
}

resource "aws_iam_policy" "controller" {
  name_prefix = "eks-alb-controller-"
  description = "AWS Load Balancer Controller v3.6.2 permissions"
  policy      = file("${path.module}/policies/iam_policy_v3.6.2.json")
  tags        = var.tags
}

resource "aws_iam_role" "controller" {
  name_prefix = "eks-alb-controller-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.this.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "system:serviceaccount:kube-system:${local.service_account_name}"
        }
      }
    }]
  })
  tags = var.tags

  lifecycle {
    precondition {
      condition     = contains(data.aws_iam_openid_connect_provider.this.client_id_list, "sts.amazonaws.com")
      error_message = "The cluster IAM OIDC provider must include sts.amazonaws.com as an audience."
    }
    precondition {
      condition     = data.aws_eks_cluster.this.vpc_config[0].vpc_id == var.vpc_id
      error_message = "vpc_id must match the EKS cluster VPC."
    }
  }
}

resource "aws_iam_role_policy_attachment" "controller" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.controller.arn
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.alb_controller_chart_version

  wait    = true
  timeout = 600
  values = [templatefile(
    "${path.module}/helm_value/aws-load-balancer-controller.yaml.tftpl",
    {
      cluster_name         = var.cluster_name
      aws_region           = var.aws_region
      vpc_id               = var.vpc_id
      replica_count        = var.replica_count
      service_account_name = local.service_account_name
      controller_role_arn  = aws_iam_role.controller.arn
      acm_certificate_arn  = var.acm_certificate_arn
    }
  )]

  depends_on = [aws_iam_role_policy_attachment.controller]

  lifecycle {
    precondition {
      condition     = var.acm_certificate_arn == null ? true : split(":", var.acm_certificate_arn)[3] == var.aws_region
      error_message = "The ACM certificate must be in the same region as the EKS cluster and ALB."
    }
  }
}
