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
  description = "Map of IRSA roles to create. Keyed by short name; each value defines the ServiceAccount binding and inline policy. When null (default), the module's built-in defaults are used: jenkins, cluster-autoscaler, fluent-bit, aws-lb-controller, external-secrets. All entries are skipped when oidc_provider_arn is empty (phase 1). Policy JSON may use the placeholders __AWS_PARTITION__, __AWS_REGION__, __AWS_ACCOUNT_ID__, __CLUSTER_NAME__."
  type = map(object({
    namespace        = string
    service_account  = string
    policy_json      = string
    role_name_suffix = optional(string)
  }))
  default = null
}

variable "inline_policy_name_suffix" {
  description = "Suffix appended to each IRSA role's map key to form the inline aws_iam_role_policy name."
  type        = string
  default     = "-policy"
}

variable "partition_placeholder" {
  description = "Literal placeholder token in policy JSON substituted with data.aws_partition.current.partition at apply time."
  type        = string
  default     = "__AWS_PARTITION__"
}

variable "region_placeholder" {
  description = "Literal placeholder token in policy JSON substituted with var.aws_region at apply time."
  type        = string
  default     = "__AWS_REGION__"
}

variable "account_id_placeholder" {
  description = "Literal placeholder token in policy JSON substituted with var.aws_account_id at apply time."
  type        = string
  default     = "__AWS_ACCOUNT_ID__"
}

variable "cluster_name_placeholder" {
  description = "Literal placeholder token in policy JSON substituted with var.cluster_name at apply time."
  type        = string
  default     = "__CLUSTER_NAME__"
}

variable "irsa_assume_role_effect" {
  description = "Effect on the IRSA assume-role policy statement."
  type        = string
  default     = "Allow"
}

variable "irsa_assume_role_action" {
  description = "Action on the IRSA assume-role policy statement (the only action used by the OIDC web-identity trust)."
  type        = string
  default     = "sts:AssumeRoleWithWebIdentity"
}

variable "irsa_assume_role_principal_type" {
  description = "Principal type on the IRSA assume-role policy statement."
  type        = string
  default     = "Federated"
}

variable "irsa_assume_role_condition_test" {
  description = "Condition test operator used for both :sub and :aud OIDC claims on the IRSA assume-role policy statement."
  type        = string
  default     = "StringEquals"
}

variable "irsa_assume_role_sub_suffix" {
  description = "OIDC issuer URL suffix that selects the subject claim in the IRSA assume-role condition (appended to var.oidc_provider_url)."
  type        = string
  default     = ":sub"
}

variable "irsa_assume_role_aud_suffix" {
  description = "OIDC issuer URL suffix that selects the audience claim in the IRSA assume-role condition (appended to var.oidc_provider_url)."
  type        = string
  default     = ":aud"
}

variable "irsa_assume_role_subject_prefix" {
  description = "Prefix for the OIDC :sub claim value identifying a Kubernetes ServiceAccount (Kubernetes-defined; followed by <namespace>:<service_account>)."
  type        = string
  default     = "system:serviceaccount:"
}

variable "irsa_assume_role_audience" {
  description = "Required value of the OIDC :aud claim for the EKS IRSA trust relationship."
  type        = string
  default     = "sts.amazonaws.com"
}
