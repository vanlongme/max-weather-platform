data "aws_region" "current" {}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-igw"
  })
}

# POC topology: public subnets only — no private subnets, no NAT Gateway, no VPC endpoints.
# Worker nodes are placed in these subnets and receive public IPs (map_public_ip_on_launch = true)
# so they can reach ECR / Open-Meteo / Cognito JWKS directly via the Internet Gateway.
#
# Subnet tags carry BOTH `kubernetes.io/role/elb=1` and `kubernetes.io/role/internal-elb=1`
# so the AWS Load Balancer Controller can place either internet-facing or internal NLBs here.
# `karpenter.sh/discovery=<cluster>` lets Karpenter's EC2NodeClass discover these subnets via
# subnetSelectorTerms.
#
# For production the recommended topology is private subnets + NAT Gateway (or VPC endpoints),
# with workers in private subnets and only LBs in public subnets.
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                        = "${var.cluster_name}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "karpenter.sh/discovery"                    = var.cluster_name
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
