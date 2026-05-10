variable "aws_region" {
  description = "AWS region to deploy resources."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name and resource prefix."
  type        = string
  default     = "max-weather"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for subnet distribution (one per AZ)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ). POC topology uses public subnets for both workers and load balancers."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
}

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.30"
}

variable "node_instance_types" {
  description = "EC2 instance types for the default managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  description = "Minimum number of EKS worker nodes in the default managed node group."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of EKS worker nodes in the default managed node group."
  type        = number
  default     = 10
}

variable "node_desired_size" {
  description = "Initial desired number of EKS worker nodes in the default managed node group."
  type        = number
  default     = 2
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days."
  type        = number
  default     = 7
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to access the EKS public API endpoint. Set to your operator IP /32."
  type        = list(string)
}

variable "cognito_domain_prefix" {
  description = "Globally unique prefix for the Cognito hosted UI domain (e.g. max-weather-abc123)."
  type        = string
}

