variable "aws_region" {
  description = "AWS region for the Secrets Manager provider."
  type        = string
}

variable "irsa_role_arn" {
  description = "IRSA IAM role ARN for the External Secrets service account."
  type        = string
}

variable "chart_version" {
  description = "Helm chart version for external-secrets."
  type        = string
  default     = "0.10.4"
}
