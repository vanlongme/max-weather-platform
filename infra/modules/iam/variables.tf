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

variable "irsa_roles" {
  description = "Map of IRSA roles to create. Keyed by short name; each value defines the ServiceAccount binding and inline policy. When null (default), the module's built-in defaults are used: jenkins, cluster-autoscaler, fluent-bit, aws-lb-controller, external-secrets. All entries are skipped when oidc_provider_arn is empty (phase 1). Policy JSON may use the placeholders __AWS_REGION__, __AWS_ACCOUNT_ID__, __CLUSTER_NAME__."
  type = map(object({
    namespace        = string
    service_account  = string
    policy_json      = string
    role_name_suffix = optional(string)
  }))
  default = null
}
