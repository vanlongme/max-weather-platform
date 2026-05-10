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
