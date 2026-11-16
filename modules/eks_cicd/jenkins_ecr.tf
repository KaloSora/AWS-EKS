locals {
  jenkins_ecr_role_managed = local.jenkins_agent_enabled && var.jenkins_ecr_role_arn == null && var.jenkins_ecr != null
  jenkins_ecr_role_arn     = var.jenkins_ecr_role_arn != null ? var.jenkins_ecr_role_arn : one(aws_iam_role.jenkins_ecr[*].arn)
  jenkins_ecr_oidc_issuer  = try(split(":oidc-provider/", var.jenkins_ecr.oidc_provider_arn)[1], null)
  jenkins_ecr_cluster_arn  = var.jenkins_ecr == null ? [] : split(":", var.jenkins_ecr.cluster_arn)
}

resource "aws_iam_role" "jenkins_ecr" {
  count = local.jenkins_ecr_role_managed ? 1 : 0

  name_prefix = "jenkins-ecr-publisher-"
  description = "IRSA role for Jenkins agents that publish to ECR"
  assume_role_policy = local.jenkins_ecr_oidc_issuer == null ? null : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = var.jenkins_ecr.oidc_provider_arn }
      Condition = {
        StringEquals = {
          "${local.jenkins_ecr_oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.jenkins_ecr_oidc_issuer}:sub" = "system:serviceaccount:${local.jenkins_agent_namespace}:${local.jenkins_agent_service_account_name}"
        }
      }
    }]
  })

  lifecycle {
    precondition {
      condition     = local.jenkins_ecr_oidc_issuer != null
      error_message = "The managed Jenkins ECR role needs the cluster IAM OIDC provider. Enable eks_csi_enabled or supply an existing role ARN."
    }
  }
}

resource "aws_iam_role_policy" "jenkins_ecr" {
  count = length(aws_iam_role.jenkins_ecr)

  name = "push-image"
  role = aws_iam_role.jenkins_ecr[count.index].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = "arn:${local.jenkins_ecr_cluster_arn[1]}:ecr:${local.jenkins_ecr_cluster_arn[3]}:${local.jenkins_ecr_cluster_arn[4]}:repository/${var.jenkins_ecr.repository_name}"
      },
    ]
  })
}
