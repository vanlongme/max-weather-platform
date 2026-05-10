variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.30"
}

variable "cluster_role_arn" {
  description = "IAM role ARN for the EKS control plane."
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs (public + private) for the EKS control plane."
  type        = list(string)
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint. Must NOT be [\"0.0.0.0/0\"]."
  type        = list(string)

  validation {
    condition     = !contains(var.allowed_cidrs, "0.0.0.0/0")
    error_message = "allowed_cidrs must not include 0.0.0.0/0. Restrict to your operator IP CIDR."
  }
}

variable "operator_principal_arn" {
  description = "IAM principal ARN (user or role) that gets cluster-admin access via access entry."
  type        = string
}

variable "jenkins_role_arn" {
  description = "IAM role ARN for Jenkins EC2; granted namespace-scoped Edit access."
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
