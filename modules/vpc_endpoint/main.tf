# Resolve the regional service names instead of assuming a partition or region.
data "aws_vpc_endpoint_service" "interface" {
  for_each = var.interface_services

  service      = each.value
  service_type = "Interface"
}

data "aws_vpc_endpoint_service" "s3" {
  count = var.enable_s3_gateway ? 1 : 0

  service      = "s3"
  service_type = "Gateway"
}

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-vpce-"
  description = "HTTPS access to VPC endpoints from private subnets"
  vpc_id      = var.vpc_id

  # No outbound rules: endpoint ENIs only need stateful response traffic.
  tags = merge(var.tags, { Name = "${var.name}-vpce" })
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = var.private_subnets

  security_group_id = aws_security_group.this.id
  description       = "HTTPS from private subnet in ${each.key}"
  cidr_ipv4         = each.value.cidr_block
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  tags              = var.tags
}

resource "aws_vpc_endpoint" "interface" {
  for_each = var.interface_services

  vpc_id              = var.vpc_id
  service_name        = data.aws_vpc_endpoint_service.interface[each.key].service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for subnet in values(var.private_subnets) : subnet.subnet_id]
  security_group_ids  = [aws_security_group.this.id]
  private_dns_enabled = true
  policy              = lookup(var.endpoint_policies, each.key, null)

  tags = merge(var.tags, { Name = "${var.name}-${each.key}-vpce" })

  lifecycle {
    precondition {
      condition = alltrue([
        for az in keys(var.private_subnets) :
        contains(data.aws_vpc_endpoint_service.interface[each.key].availability_zones, az)
      ])
      error_message = "The selected endpoint service must support every configured AZ. Check regional service availability or adjust the endpoint subnet selection."
    }
  }

  depends_on = [aws_vpc_security_group_ingress_rule.https]
}

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_gateway ? 1 : 0

  vpc_id            = var.vpc_id
  service_name      = data.aws_vpc_endpoint_service.s3[0].service_name
  vpc_endpoint_type = "Gateway"
  route_table_ids   = distinct([for subnet in values(var.private_subnets) : subnet.route_table_id])
  policy            = lookup(var.endpoint_policies, "s3", null)

  tags = merge(var.tags, { Name = "${var.name}-s3-vpce" })
}
