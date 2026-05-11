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
