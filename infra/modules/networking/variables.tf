variable "cluster_name" {
  description = "EKS cluster name, used for subnet tagging (kubernetes.io/cluster/<name>, karpenter.sh/discovery) and resource naming."
  type        = string
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
