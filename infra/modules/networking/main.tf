locals {
  cluster_tag_value = var.eks_cluster_name == "" ? var.name : var.eks_cluster_name
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(var.tags, {
    Name = "${var.name}${var.vpc_name_suffix}"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name}${var.internet_gateway_name_suffix}"
  })
}

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(var.tags, {
    Name                                                             = "${var.name}${var.public_subnet_name_prefix}${var.availability_zones[count.index]}${var.public_subnet_name_suffix}"
    (var.subnet_tag_role_elb_key)                                    = var.subnet_tag_role_elb_value
    (var.subnet_tag_role_internal_elb_key)                           = var.subnet_tag_role_elb_value
    "${var.subnet_tag_cluster_key_prefix}${local.cluster_tag_value}" = var.subnet_tag_cluster_value
    (var.subnet_tag_karpenter_discovery_key)                         = local.cluster_tag_value
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = var.public_route_destination_cidr_block
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.name}${var.public_route_table_name_suffix}"
  })
}

resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
