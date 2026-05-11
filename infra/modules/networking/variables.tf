variable "name" {
  description = "Name prefix applied to every networking resource (typically the master_prefix from the composition, e.g. 'poc-max-weather'). Used for the Name tag on the VPC, IGW, subnets, and route table."
  type        = string
}

variable "eks_cluster_name" {
  description = "Full EKS cluster name used as the VALUE of the kubernetes.io/cluster/<cluster_name> subnet tag and as the value of the karpenter.sh/discovery subnet tag. Must match the actual EKS cluster name produced by the eks module (typically <var.name><eks.cluster_name_suffix>, e.g. 'poc-max-weather-cluster'). Empty string falls back to var.name for backward compatibility."
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones for subnet distribution. Length must match the number of public subnet CIDRs."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ). Workers are placed in these subnets in the POC topology."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
}

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
  description = "Common tags to apply to all resources created by this module."
  type        = map(string)
  default     = {}
}

variable "vpc_name_suffix" {
  description = "Suffix appended to var.name for the VPC Name tag."
  type        = string
  default     = "-vpc"
}

variable "internet_gateway_name_suffix" {
  description = "Suffix appended to var.name for the Internet Gateway Name tag."
  type        = string
  default     = "-igw"
}

variable "public_subnet_name_prefix" {
  description = "Prefix appended to var.name (followed by the AZ name) for each public subnet's Name tag."
  type        = string
  default     = "-public-"
}

variable "public_subnet_name_suffix" {
  description = "Suffix appended after the AZ component of each public subnet's Name tag (e.g. '-subnet' produces 'poc-max-weather-public-us-east-1a-subnet'). Default empty string preserves the historical naming."
  type        = string
  default     = ""
}

variable "public_route_table_name_suffix" {
  description = "Suffix appended to var.name for the public route table Name tag."
  type        = string
  default     = "-public-rt"
}

variable "map_public_ip_on_launch" {
  description = "Whether public subnets assign a public IPv4 to instances launched into them. POC topology requires true so worker nodes can reach ECR/Open-Meteo without a NAT Gateway."
  type        = bool
  default     = true
}

variable "public_route_destination_cidr_block" {
  description = "Destination CIDR for the default route in the public route table (typically 0.0.0.0/0 for IPv4 internet egress via the IGW)."
  type        = string
  default     = "0.0.0.0/0"
}

variable "subnet_tag_role_elb_key" {
  description = "Subnet tag key consumed by the AWS Load Balancer Controller to discover subnets eligible for internet-facing load balancers."
  type        = string
  default     = "kubernetes.io/role/elb"
}

variable "subnet_tag_role_internal_elb_key" {
  description = "Subnet tag key consumed by the AWS Load Balancer Controller to discover subnets eligible for internal load balancers."
  type        = string
  default     = "kubernetes.io/role/internal-elb"
}

variable "subnet_tag_role_elb_value" {
  description = "Tag value applied to public subnets for the kubernetes.io/role/elb and kubernetes.io/role/internal-elb keys."
  type        = string
  default     = "1"
}

variable "subnet_tag_cluster_key_prefix" {
  description = "Prefix for the EKS cluster subnet discovery tag. The full EKS cluster name (var.eks_cluster_name, falling back to var.name) is appended to form the full key (kubernetes.io/cluster/<cluster_name>)."
  type        = string
  default     = "kubernetes.io/cluster/"
}

variable "subnet_tag_cluster_value" {
  description = "Tag value for the kubernetes.io/cluster/<cluster_name> subnet discovery tag."
  type        = string
  default     = "shared"
}

variable "subnet_tag_karpenter_discovery_key" {
  description = "Subnet tag key consumed by Karpenter EC2NodeClass.subnetSelectorTerms to discover subnets where it may launch nodes. Tag value is the full EKS cluster name (var.eks_cluster_name, falling back to var.name)."
  type        = string
  default     = "karpenter.sh/discovery"
}
