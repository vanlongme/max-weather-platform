variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "VPC ID where the cluster lives."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for managed node groups and control plane ENIs. POC topology passes the public subnet IDs here; production should pass private subnet IDs."
  type        = list(string)
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint."
  type        = list(string)

  validation {
    condition     = !contains(var.allowed_cidrs, "0.0.0.0/0")
    error_message = "allowed_cidrs must not include 0.0.0.0/0. Restrict to your operator IP CIDR."
  }
}

variable "operator_principal_arn" {
  description = "IAM principal ARN granted cluster-admin via access entry."
  type        = string
}

variable "jenkins_role_arn" {
  description = "Jenkins IRSA role ARN granted namespace-scoped Edit access on weather-staging/weather-prod. Empty during phase 1 (before IAM module creates the IRSA role); the access entry is omitted when empty."
  type        = string
  default     = ""
}

variable "eks_managed_node_groups" {
  description = "Map of EKS managed node group definitions, keyed by node group name. Each entry is passed through to the upstream eks_managed_node_groups input."
  type = map(object({
    name           = optional(string)
    instance_types = optional(list(string), ["t3.medium"])
    min_size       = optional(number, 2)
    max_size       = optional(number, 10)
    desired_size   = optional(number, 2)
    capacity_type  = optional(string, "ON_DEMAND")
    ami_type       = optional(string, "AL2023_x86_64_STANDARD")
    disk_size      = optional(number, 20)
    labels         = optional(map(string), {})
    taints         = optional(map(object({ key = string, value = optional(string), effect = string })), {})
    tags           = optional(map(string), {})
  }))
  default = {
    general = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 10
      desired_size   = 2
      labels         = { role = "general" }
    }
  }
}

variable "eks_managed_node_group_defaults" {
  description = "Defaults applied to every managed node group. Per-group overrides win."
  type        = any
  default = {
    attach_cluster_primary_security_group = false
  }
}

variable "cluster_addons" {
  description = "Map of EKS add-ons to enable. Passed through to the upstream cluster_addons input."
  type        = any
  default = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
  }
}

variable "access_entries" {
  description = "Additional access entries merged after operator + jenkins entries derived from operator_principal_arn / jenkins_role_arn. User-supplied entries win on key collision."
  type        = any
  default     = {}
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
