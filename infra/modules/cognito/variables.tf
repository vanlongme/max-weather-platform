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
