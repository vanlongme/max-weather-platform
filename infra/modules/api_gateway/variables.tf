variable "name" {
  description = "Resource name prefix (typically master_prefix, e.g. 'poc-max-weather')."
  type        = string
}

variable "lambda_authorizer_arn" {
  description = "ARN of the Lambda function used as the JWT authorizer."
  type        = string
}

variable "lambda_function_name" {
  description = "Name of the Lambda function (used for aws_lambda_permission)."
  type        = string
}

variable "nlb_dns" {
  description = "DNS name of the Network Load Balancer fronting the EKS ingress."
  type        = string
}

variable "ingress_host" {
  description = "Static Host header value injected into the upstream integration so ingress-nginx host-based routing matches. API Gateway v2 only supports static (non-templated) Host overwrites."
  type        = string
}

variable "stages" {
  description = "Map of API Gateway stages to create. Stage isolation is enforced by the Lambda authorizer per-stage (issuer/scope/secret); routes and integrations are API-level and shared across stages."
  type = map(object({
    secret_arn = string
    issuer     = string
    scope      = string
  }))
}

variable "tags" {
  description = "Common tags to apply to all resources."
  type        = map(string)
  default     = {}
}

###############################################################################
# Optional VPC Link mode (private cluster).
#
# When `vpc_link_subnet_ids` is non-empty, the module provisions an
# `aws_apigatewayv2_vpc_link` and switches both integrations to
# `connection_type = "VPC_LINK"` using the supplied NLB listener ARN as the
# integration URI. When empty (default), the module retains the original
# `connection_type = "INTERNET"` behavior using `var.nlb_dns` (backward
# compatible).
###############################################################################

variable "vpc_link_subnet_ids" {
  description = "Private subnet IDs (one per AZ) for the API Gateway VPC Link ENIs. Supply the same subnets the internal NLB lives in. Empty list (default) disables VPC Link and keeps connection_type=INTERNET."
  type        = list(string)
  default     = []
}

variable "vpc_link_security_group_ids" {
  description = "Security group IDs attached to the VPC Link ENIs. Required (and used) only when `vpc_link_subnet_ids` is non-empty. The SG only needs egress to the NLB targets (typically the VPC CIDR on the workload ports)."
  type        = list(string)
  default     = []
}

variable "nlb_listener_arn" {
  description = "ARN of the NLB listener (e.g. port 80) that integrations target when VPC Link mode is enabled. Required (and used) only when `vpc_link_subnet_ids` is non-empty; in INTERNET mode the module uses `var.nlb_dns` instead."
  type        = string
  default     = ""
}
