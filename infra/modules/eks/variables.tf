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
  description = "Jenkins EC2 role ARN granted namespace-scoped Edit access."
  type        = string
}

variable "node_instance_types" {
  description = "EC2 instance types for the default managed node group (system + cluster-autoscaler workloads)."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  description = "Minimum nodes in the default managed node group."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum nodes in the default managed node group (cluster-autoscaler upper bound)."
  type        = number
  default     = 10
}

variable "node_desired_size" {
  description = "Initial desired node count in the default managed node group."
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Root EBS volume size in GiB for nodes in the default managed node group."
  type        = number
  default     = 20
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
