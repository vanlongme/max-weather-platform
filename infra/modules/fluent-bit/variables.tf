variable "aws_region" {
  description = "AWS region for CloudWatch Logs destination."
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group name for application logs."
  type        = string
}

variable "irsa_role_arn" {
  description = "IRSA IAM role ARN for Fluent Bit service account."
  type        = string
}

variable "chart_version" {
  description = "Helm chart version for aws-for-fluent-bit."
  type        = string
  default     = "0.1.34"
}
