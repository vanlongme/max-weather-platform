variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "aws_region" {
  description = "AWS region."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the load balancer controller."
  type        = string
}

variable "irsa_role_arn" {
  description = "IRSA IAM role ARN for the AWS Load Balancer Controller service account."
  type        = string
}

variable "chart_version" {
  description = "Helm chart version for aws-load-balancer-controller."
  type        = string
  default     = "1.8.2"
}

variable "replica_count" {
  description = "Number of controller replicas."
  type        = number
  default     = 2
}
