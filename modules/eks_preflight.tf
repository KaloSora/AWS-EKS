# Keep this lookup outside module.eks so its NAT dependency cannot defer the
# account-independent instance-type checks until apply. No AWS resource is created.
data "aws_ec2_instance_types" "eks_compatible" {
  filter {
    name   = "instance-type"
    values = var.eks_node_instance_types
  }

  filter {
    name   = "processor-info.supported-architecture"
    values = ["x86_64"]
  }

  dynamic "filter" {
    for_each = var.eks_require_free_tier_eligible ? [1] : []
    content {
      name   = "free-tier-eligible"
      values = ["true"]
    }
  }
}

resource "terraform_data" "eks_preflight" {
  input = var.eks_node_instance_types

  lifecycle {
    precondition {
      condition     = length(var.eks_node_instance_types) >= 1 && length(var.eks_node_instance_types) <= 20
      error_message = "Configure 1 to 20 EKS node instance types."
    }
    precondition {
      condition     = length(setsubtract(toset(var.eks_node_instance_types), toset(data.aws_ec2_instance_types.eks_compatible.instance_types))) == 0
      error_message = "EKS node instance types failed the regional x86_64/Free Tier eligibility check. Choose supported types or disable eks_require_free_tier_eligible only if your account plan permits paid types."
    }
  }
}
