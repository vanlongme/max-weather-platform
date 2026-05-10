variable "cluster_name" {
  description = "EKS cluster name for auto-discovery."
  type        = string
}

variable "aws_region" {
  description = "AWS region where the cluster runs."
  type        = string
}

variable "irsa_role_arn" {
  description = "IRSA IAM role ARN for Cluster Autoscaler service account."
  type        = string
}

variable "chart_version" {
  description = "Helm chart version for cluster-autoscaler."
  type        = string
  default     = "9.37.0"
}
