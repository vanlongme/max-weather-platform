variable "name" {
  description = "Name prefix applied to every IAM role (typically the master_prefix from the composition, e.g. 'poc-max-weather'). Each role is named <name>-<per-entry role_name_suffix or map_key><module role_name_suffix>. Also substitutes the __CLUSTER_NAME__ placeholder in inline policy JSON."
  type        = string
}

variable "aws_region" {
  description = "AWS region used for ARN construction in policies (substitutes __AWS_REGION__)."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID for policy ARN construction (substitutes __AWS_ACCOUNT_ID__)."
  type        = string
}

variable "tags" {
  description = "Common tags to apply to all roles."
  type        = map(string)
  default     = {}
}

variable "role_name_suffix" {
  description = "Suffix appended to every IAM role name after the per-entry portion. Default '-role' makes role names self-describing (e.g. 'poc-max-weather-jenkins-role')."
  type        = string
  default     = "-role"
}

variable "service_roles" {
  description = "Map of AWS service-principal IAM roles (EC2, Lambda, ECS task, etc.). Keyed by short name. service_principals lists the AWS service principals the role can be assumed by (e.g. [\"lambda.amazonaws.com\"]). policy_json is the inline policy; managed_policy_arns attaches AWS-managed policies. Default ships one built-in: lambda_authorizer (Lambda execution role with Secrets Manager access scoped to the authorizer JWT secret)."
  type = map(object({
    service_principals  = list(string)
    policy_json         = optional(string)
    managed_policy_arns = optional(list(string), [])
    role_name_suffix    = optional(string)
  }))
  default = {
    lambda_authorizer = {
      service_principals  = ["lambda.amazonaws.com"]
      managed_policy_arns = ["arn:__AWS_PARTITION__:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
      policy_json         = <<-EOT
        {
          "Version": "2012-10-17",
          "Statement": [
            {
              "Sid": "AllowGetSecret",
              "Effect": "Allow",
              "Action": "secretsmanager:GetSecretValue",
              "Resource": "arn:__AWS_PARTITION__:secretsmanager:__AWS_REGION__:__AWS_ACCOUNT_ID__:secret:__CLUSTER_NAME__-authorizer-jwt-secret-*"
            }
          ]
        }
      EOT
    }
  }
}

variable "irsa_roles" {
  description = "Map of IAM Roles for Service Accounts (OIDC web-identity trust). Empty by default. Requires var.oidc_provider_arn + var.oidc_provider_url to be non-empty; entries are skipped otherwise. Prefer pod_identity_roles for new workloads on EKS 1.30+."
  type = map(object({
    namespace        = string
    service_account  = string
    policy_json      = string
    role_name_suffix = optional(string)
  }))
  default = {}
}

variable "pod_identity_roles" {
  description = "Map of EKS Pod Identity roles (pods.eks.amazonaws.com trust). When null, the module ships the built-in workload roles: jenkins, cluster-autoscaler, fluent-bit, external-secrets, ebs-csi-controller, efs-csi-controller. Override (replaces defaults entirely — re-declare any built-ins to keep). The module creates roles + inline policies + managed-policy attachments; Pod Identity associations are created by the eks module via the role_bindings output. policy_json is optional — omit when managed_policy_arns alone is sufficient (e.g. EBS/EFS CSI use AWS-managed policies)."
  type = map(object({
    namespace           = string
    service_account     = string
    policy_json         = optional(string)
    managed_policy_arns = optional(list(string), [])
    role_name_suffix    = optional(string)
  }))
  default = null
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider for IRSA trust relationships. Required when irsa_roles is non-empty. Sourced from the eks module."
  type        = string
  default     = ""
}

variable "oidc_provider_url" {
  description = "URL of the EKS OIDC provider (without https:// prefix). Required when irsa_roles is non-empty. Sourced from the eks module."
  type        = string
  default     = ""
}

variable "inline_policy_name_suffix" {
  description = "Suffix appended to each role's map key to form the inline aws_iam_role_policy name."
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
  description = "Literal placeholder token in policy JSON substituted with var.name at apply time. Named for backward compatibility — the substituted value is the resource name prefix shared across the deployment."
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
  description = "Prefix for the OIDC :sub claim value identifying a Kubernetes ServiceAccount."
  type        = string
  default     = "system:serviceaccount:"
}

variable "irsa_assume_role_audience" {
  description = "Required value of the OIDC :aud claim for the EKS IRSA trust relationship."
  type        = string
  default     = "sts.amazonaws.com"
}

variable "pod_identity_assume_role_effect" {
  description = "Effect on the Pod Identity assume-role policy statement."
  type        = string
  default     = "Allow"
}

variable "pod_identity_assume_role_actions" {
  description = "Actions on the Pod Identity assume-role policy statement. Pod Identity requires both sts:AssumeRole (to assume) and sts:TagSession (to tag the session with EKS context)."
  type        = list(string)
  default     = ["sts:AssumeRole", "sts:TagSession"]
}

variable "pod_identity_assume_role_principal_type" {
  description = "Principal type on the Pod Identity assume-role policy statement."
  type        = string
  default     = "Service"
}

variable "pod_identity_assume_role_principal_service" {
  description = "Service principal that EKS Pod Identity uses to assume workload roles."
  type        = string
  default     = "pods.eks.amazonaws.com"
}

variable "service_role_assume_effect" {
  description = "Effect on the service-role assume-role policy statement."
  type        = string
  default     = "Allow"
}

variable "service_role_assume_actions" {
  description = "Actions on the service-role assume-role policy statement."
  type        = list(string)
  default     = ["sts:AssumeRole"]
}

variable "service_role_assume_principal_type" {
  description = "Principal type on the service-role assume-role policy statement."
  type        = string
  default     = "Service"
}
