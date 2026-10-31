data "aws_ec2_instance_types" "compatible" {
  filter {
    name   = "instance-type"
    values = var.instance_types
  }

  filter {
    name   = "processor-info.supported-architecture"
    values = ["x86_64"]
  }

  dynamic "filter" {
    for_each = var.require_free_tier_eligible ? [1] : []
    content {
      name   = "free-tier-eligible"
      values = ["true"]
    }
  }
}
