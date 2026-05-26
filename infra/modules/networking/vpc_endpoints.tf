resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_vpc_endpoints ? 1 : 0

  name        = "${var.name}${var.vpc_endpoint_sg_name_suffix}"
  description = "Allows 443/TCP from inside the VPC to AWS service interface endpoints"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name}${var.vpc_endpoint_sg_name_suffix}"
  })
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https" {
  count = var.enable_vpc_endpoints ? 1 : 0

  security_group_id = aws_security_group.vpc_endpoints[0].id
  description       = "HTTPS from VPC CIDR to interface endpoints"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_endpoint" "interface" {
  for_each = var.enable_vpc_endpoints ? var.vpc_interface_endpoints : {}

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.vpc_endpoint_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = var.vpc_endpoint_private_dns_enabled

  tags = merge(var.tags, {
    Name = "${var.name}-vpce-${each.key}"
  })
}

resource "aws_vpc_endpoint" "s3_gateway" {
  count = var.enable_vpc_endpoints && var.enable_s3_gateway_endpoint ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.vpc_endpoint_route_table_ids

  tags = merge(var.tags, {
    Name = "${var.name}-vpce-s3"
  })
}
