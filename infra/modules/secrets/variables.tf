variable "cluster_name" {
  description = "EKS cluster name prefix."
  type        = string
}

variable "cluster_name_placeholder" {
  description = "Literal placeholder token in secret names that is substituted with var.cluster_name at apply time."
  type        = string
  default     = "__CLUSTER_NAME__"
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Map of Secrets Manager secrets to create. Map keys become the resource address. Each value's `name` may interpolate `__CLUSTER_NAME__` (replaced by var.cluster_name). When `initial_value` is null, no secret_version is created (caller is responsible for populating). All secrets ignore secret_string changes after first apply (caller manages updates externally)."
  type = map(object({
    name                    = string
    description             = optional(string)
    initial_value           = optional(string)
    recovery_window_in_days = optional(number, 7)
  }))
  default = {
    cognito_client_secret = {
      name          = "/__CLUSTER_NAME__/cognito/client-secret"
      description   = "Cognito app client secret for weather-api OAuth2."
      initial_value = "PLACEHOLDER_REPLACE_AFTER_COGNITO_APPLY"
    }
    app_config = {
      name          = "/__CLUSTER_NAME__/app/config"
      description   = "weather-api application runtime configuration."
      initial_value = "{\"OPEN_METEO_BASE_URL\":\"https://api.open-meteo.com/v1\",\"PORT\":\"3000\"}"
    }
  }
}
