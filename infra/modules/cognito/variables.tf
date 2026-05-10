variable "cluster_name" {
  description = "Project prefix for resource naming."
  type        = string
}

variable "domain_prefix" {
  description = "Unique prefix for the Cognito hosted UI domain (must be globally unique)."
  type        = string
}

variable "resource_server_identifier" {
  description = "URI identifier for the resource server (e.g. https://weather-api.example.com)."
  type        = string
  default     = "weather-api"
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}

variable "user_pool_name_suffix" {
  description = "Suffix appended to var.cluster_name to form the Cognito user pool name."
  type        = string
  default     = "-user-pool"
}

variable "password_policy" {
  description = "Cognito user pool password policy."
  type = object({
    minimum_length    = optional(number, 12)
    require_lowercase = optional(bool, true)
    require_uppercase = optional(bool, true)
    require_numbers   = optional(bool, true)
    require_symbols   = optional(bool, true)
  })
  default = {}
}

variable "resource_server_name" {
  description = "Human-readable display name of the Cognito resource server."
  type        = string
  default     = "Weather API"
}

variable "resource_server_scope_name" {
  description = "Short name of the OAuth2 scope exposed by the resource server."
  type        = string
  default     = "read"
}

variable "resource_server_scope_description" {
  description = "Human-readable description of the OAuth2 scope exposed by the resource server."
  type        = string
  default     = "Read access to weather API."
}

variable "client_name_suffix" {
  description = "Suffix appended to the per-client name segment to form the final app-client name."
  type        = string
  default     = "-client"
}

variable "default_oauth_scope_suffix" {
  description = "Scope suffix appended to var.resource_server_identifier when an app client does not specify allowed_oauth_scopes."
  type        = string
  default     = "/read"
}

variable "cognito_endpoint_scheme" {
  description = "URL scheme used for Cognito-derived output URLs (token endpoint, JWKS URI)."
  type        = string
  default     = "https"
}

variable "cognito_domain_suffix" {
  description = "Suffix appended to var.domain_prefix when constructing the Cognito hosted UI host segment (typically empty)."
  type        = string
  default     = ""
}

variable "cognito_domain_root" {
  description = "Root domain for the Cognito hosted UI in the target region/partition."
  type        = string
  default     = "amazoncognito.com"
}

variable "cognito_token_path" {
  description = "URL path of the Cognito OAuth2 token endpoint."
  type        = string
  default     = "/oauth2/token"
}

variable "cognito_idp_domain_prefix" {
  description = "Subdomain prefix of the regional Cognito Identity Provider host used to build the JWKS URI."
  type        = string
  default     = "cognito-idp"
}

variable "aws_dns_suffix" {
  description = "DNS suffix for the AWS partition (e.g. amazonaws.com for the public partition)."
  type        = string
  default     = "amazonaws.com"
}

variable "jwks_path" {
  description = "URL path of the Cognito user pool JWKS document."
  type        = string
  default     = "/.well-known/jwks.json"
}

variable "primary_client_key" {
  description = "Map key in var.app_clients whose client_id/client_secret are exposed via the back-compat outputs client_id and client_secret."
  type        = string
  default     = "weather_api"
}

variable "app_clients" {
  description = "Map of Cognito user pool app clients to create, keyed by short name. Defaults provide the weather-api client (client_credentials M2M flow with read scope on the resource server). Final client name = \"$${cluster_name}-$${name_suffix}-client\" where name_suffix defaults to the map key."
  type = map(object({
    name_suffix                          = optional(string)
    generate_secret                      = optional(bool, true)
    allowed_oauth_flows_user_pool_client = optional(bool, true)
    allowed_oauth_flows                  = optional(list(string), ["client_credentials"])
    allowed_oauth_scopes                 = optional(list(string))
    supported_identity_providers         = optional(list(string), ["COGNITO"])
  }))
  default = {
    weather_api = {
      name_suffix = "weather-api"
    }
  }
}
