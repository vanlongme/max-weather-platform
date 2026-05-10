variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN for EKS worker nodes."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs where nodes are launched."
  type        = list(string)
}

variable "instance_types" {
  description = "EC2 instance types for the node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "min_size" {
  description = "Minimum number of nodes in the group."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of nodes in the group."
  type        = number
  default     = 10
}

variable "desired_size" {
  description = "Initial desired number of nodes."
  type        = number
  default     = 2
}

variable "disk_size" {
  description = "Root EBS volume size in GiB for each node."
  type        = number
  default     = 20
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
