variable "cluster_name" {
  description = "EKS cluster name, used for role naming and policies."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider for IRSA trust relationships. Sourced from the eks module."
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS OIDC provider (without https:// prefix). Sourced from the eks module."
  type        = string
}

variable "aws_region" {
  description = "AWS region used for ARN construction in policies."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID for policy ARN construction."
  type        = string
}

variable "tags" {
  description = "Common tags to apply to all resources."
  type        = map(string)
  default     = {}
}
