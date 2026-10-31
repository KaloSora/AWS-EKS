data "aws_partition" "current" {}

data "aws_ec2_instance_type" "this" {
  instance_type = var.instance_type
}

locals {
  architecture = contains(data.aws_ec2_instance_type.this.supported_architectures, "arm64") ? "arm64" : "x86_64"
  ingress_rules = {
    for pair in setproduct(keys(var.private_subnets), var.allowed_tcp_ports) :
    "${pair[0]}-${pair[1]}" => {
      cidr_block = var.private_subnets[pair[0]].cidr_block
      port       = pair[1]
    }
  }
}

data "aws_ssm_parameter" "ami" {
  count = var.ami_id == null ? 1 : 0

  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${local.architecture}"
}

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-nat-"
  description = "NAT forwarding from private subnets; no inbound SSH"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-nat" })
}

resource "aws_vpc_security_group_ingress_rule" "clients" {
  for_each = local.ingress_rules

  security_group_id = aws_security_group.this.id
  description       = "NAT TCP ${each.value.port} from private subnet"
  cidr_ipv4         = each.value.cidr_block
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  tags              = var.tags
}

resource "aws_vpc_security_group_egress_rule" "internet" {
  for_each = { for port in var.allowed_tcp_ports : tostring(port) => port }

  security_group_id = aws_security_group.this.id
  description       = "Outbound TCP ${each.value}"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  tags              = var.tags
}

# Keep the ENI/EIP stable across instance replacement. Disable source/destination
# checks on the ENI so it can forward packets addressed to other hosts.
resource "aws_network_interface" "this" {
  subnet_id         = var.public_subnet_id
  security_groups   = [aws_security_group.this.id]
  source_dest_check = false
  tags              = merge(var.tags, { Name = "${var.name}-nat" })
}

resource "aws_eip" "this" {
  domain            = "vpc"
  network_interface = aws_network_interface.this.id
  tags              = merge(var.tags, { Name = "${var.name}-nat" })
}

resource "aws_iam_role" "this" {
  name_prefix = "${var.name}-nat-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name_prefix = "${var.name}-nat-"
  role        = aws_iam_role.this.name
  tags        = var.tags
}

resource "aws_instance" "this" {
  ami                  = var.ami_id != null ? var.ami_id : nonsensitive(data.aws_ssm_parameter.ami[0].value)
  instance_type        = var.instance_type
  iam_instance_profile = aws_iam_instance_profile.this.name

  primary_network_interface {
    network_interface_id = aws_network_interface.this.id
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  # Avoid surplus CPU credit charges on supported burstable instance families.
  dynamic "credit_specification" {
    for_each = can(regex("^t[234]", var.instance_type)) ? [1] : []
    content {
      cpu_credits = "standard"
    }
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    private_cidrs = sort(distinct([for subnet in values(var.private_subnets) : subnet.cidr_block]))
  })
  user_data_replace_on_change = true

  tags        = merge(var.tags, { Name = "${var.name}-nat" })
  volume_tags = var.tags

  # The ENI must already have its EIP and firewall rules when cloud-init runs.
  depends_on = [
    aws_eip.this,
    aws_iam_role_policy_attachment.ssm,
    aws_vpc_security_group_ingress_rule.clients,
    aws_vpc_security_group_egress_rule.internet,
  ]
}

resource "aws_route" "private_default" {
  for_each = var.private_subnets

  route_table_id         = each.value.route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.this.id

  depends_on = [aws_instance.this]
}
