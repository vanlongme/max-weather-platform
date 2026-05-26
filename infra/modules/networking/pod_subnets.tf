# VPC CNI custom networking ("2nd networking"): pods get IPs from a secondary
# CIDR block attached to the VPC. Frees the primary CIDR (small / RFC1918) for
# nodes + AWS services and lets pods scale into a large non-routable range
# (commonly 100.64.0.0/16). Caller must wire the VPC CNI addon and ENIConfig
# CRs (see eks module + envs/poc).
# https://docs.aws.amazon.com/eks/latest/userguide/cni-custom-network.html

resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  count = length(var.secondary_vpc_cidrs)

  vpc_id     = aws_vpc.main.id
  cidr_block = var.secondary_vpc_cidrs[count.index]
}

resource "aws_subnet" "pod" {
  count = length(var.pod_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.pod_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name                                                             = "${var.name}${var.pod_subnet_name_prefix}${var.availability_zones[count.index]}"
    (var.subnet_tag_role_internal_elb_key)                           = var.subnet_tag_role_elb_value
    "${var.subnet_tag_cluster_key_prefix}${local.cluster_tag_value}" = var.subnet_tag_cluster_value
    (var.subnet_tag_karpenter_discovery_key)                         = local.cluster_tag_value
  })

  depends_on = [aws_vpc_ipv4_cidr_block_association.secondary]
}

resource "aws_route_table_association" "pod" {
  count = length(aws_subnet.pod) > 0 && length(aws_route_table.private) > 0 ? length(aws_subnet.pod) : 0

  subnet_id      = aws_subnet.pod[count.index].id
  route_table_id = aws_route_table.private[0].id
}
