variable "name" {
  description = "Name prefix applied to every networking resource (typically the master_prefix from the composition, e.g. 'poc-max-weather')."
  type        = string
}

variable "eks_cluster_name" {
  description = "Full EKS cluster name used as the VALUE of the kubernetes.io/cluster/<cluster_name> subnet tag and as the value of the karpenter.sh/discovery subnet tag. Empty string falls back to var.name."
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones for subnet distribution. Length must match each provided subnet CIDR list."
  type        = list(string)
}

###############################################################################
# Public subnets — optional. Empty list skips public-tier creation entirely
# (fully-private topology).
###############################################################################

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ). Set to [] to skip public subnets entirely (fully-private cluster topology)."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
}

###############################################################################
# Private subnets — optional. Empty list skips private-tier creation entirely
# (legacy public-only POC topology).
###############################################################################

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ). Workers in a fully-private cluster live here. Set to [] to skip."
  type        = list(string)
  default     = []
}

variable "secondary_vpc_cidrs" {
  description = "Additional CIDR blocks to associate with the VPC. Required for VPC CNI custom networking ('2nd networking') so pods can use IPs from a separate, large range (commonly 100.64.0.0/16) while nodes stay on the primary CIDR. Empty = feature disabled."
  type        = list(string)
  default     = []
}

variable "pod_subnet_cidrs" {
  description = "CIDR blocks for pod subnets (one per AZ) carved from secondary_vpc_cidrs. VPC CNI custom networking assigns pod IPs from these subnets via ENIConfig CRs (caller-applied). Must lie inside secondary_vpc_cidrs. Empty = feature disabled."
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "Whether to create a single NAT Gateway (in the first public subnet) and route private subnets through it. When false (recommended for fully-private with VPC endpoints), private subnets have no default route to the internet."
  type        = bool
  default     = false
}

###############################################################################
# VPC endpoints — required for fully-private EKS clusters.
# https://docs.aws.amazon.com/eks/latest/userguide/private-clusters.html
###############################################################################

variable "enable_vpc_endpoints" {
  description = "Whether to create the VPC endpoints required for a fully-private EKS cluster (interface + S3 gateway)."
  type        = bool
  default     = false
}

variable "vpc_interface_endpoints" {
  description = "Map of interface VPC endpoints to create. Key = service short name; value = service suffix appended to com.amazonaws.<region>. Default ships the canonical EKS-private-cluster set (ec2, ecr.api, ecr.dkr, sts, logs, eks, eks-auth, kms, sqs, autoscaling, elasticloadbalancing, ssm, ssmmessages, ec2messages)."
  type        = map(string)
  default = {
    ec2                  = "ec2"
    ecr_api              = "ecr.api"
    ecr_dkr              = "ecr.dkr"
    sts                  = "sts"
    logs                 = "logs"
    eks                  = "eks"
    eks_auth             = "eks-auth"
    kms                  = "kms"
    sqs                  = "sqs"
    autoscaling          = "autoscaling"
    elasticloadbalancing = "elasticloadbalancing"
    ssm                  = "ssm"
    ssmmessages          = "ssmmessages"
    ec2messages          = "ec2messages"
  }
}

variable "enable_s3_gateway_endpoint" {
  description = "Whether to create the S3 gateway endpoint. Required for ECR image layer pulls in a fully-private cluster."
  type        = bool
  default     = true
}

variable "vpc_endpoint_private_dns_enabled" {
  description = "Whether private DNS is enabled on interface endpoints. Required so SDK calls to *.amazonaws.com hostnames resolve to endpoint ENIs."
  type        = bool
  default     = true
}

###############################################################################
# Misc + tags
###############################################################################

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC."
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS support in the VPC."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "map_public_ip_on_launch" {
  description = "Whether public subnets assign a public IPv4 to instances launched into them."
  type        = bool
  default     = true
}

variable "public_route_destination_cidr_block" {
  description = "Destination CIDR for the default route in the public route table."
  type        = string
  default     = "0.0.0.0/0"
}

###############################################################################
# Subnet tagging (EKS / Karpenter / ELB discovery)
###############################################################################

variable "subnet_tag_role_elb_key" {
  description = "Subnet tag key consumed by the AWS Load Balancer Controller for internet-facing LBs."
  type        = string
  default     = "kubernetes.io/role/elb"
}

variable "subnet_tag_role_internal_elb_key" {
  description = "Subnet tag key consumed by the AWS Load Balancer Controller for internal LBs."
  type        = string
  default     = "kubernetes.io/role/internal-elb"
}

variable "subnet_tag_role_elb_value" {
  description = "Tag value applied to subnets for the kubernetes.io/role/elb and internal-elb keys."
  type        = string
  default     = "1"
}

variable "subnet_tag_cluster_key_prefix" {
  description = "Prefix for the EKS cluster subnet discovery tag. Full key = <prefix><cluster_name>."
  type        = string
  default     = "kubernetes.io/cluster/"
}

variable "subnet_tag_cluster_value" {
  description = "Tag value for the kubernetes.io/cluster/<cluster_name> subnet discovery tag."
  type        = string
  default     = "shared"
}

variable "subnet_tag_karpenter_discovery_key" {
  description = "Subnet tag key consumed by Karpenter EC2NodeClass.subnetSelectorTerms."
  type        = string
  default     = "karpenter.sh/discovery"
}

###############################################################################
# Name suffixes (rarely overridden)
###############################################################################

variable "vpc_name_suffix" {
  type    = string
  default = "-vpc"
}

variable "internet_gateway_name_suffix" {
  type    = string
  default = "-igw"
}

variable "public_subnet_name_prefix" {
  type    = string
  default = "-public-"
}

variable "public_subnet_name_suffix" {
  type    = string
  default = ""
}

variable "private_subnet_name_prefix" {
  type    = string
  default = "-private-"
}

variable "pod_subnet_name_prefix" {
  type    = string
  default = "-pod-"
}

variable "public_route_table_name_suffix" {
  type    = string
  default = "-public-rt"
}

variable "private_route_table_name_suffix" {
  type    = string
  default = "-private-rt"
}

variable "nat_gateway_name_suffix" {
  type    = string
  default = "-nat"
}

variable "nat_eip_name_suffix" {
  type    = string
  default = "-nat-eip"
}

variable "vpc_endpoint_sg_name_suffix" {
  type    = string
  default = "-vpce-sg"
}
