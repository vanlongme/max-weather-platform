variable "chart_version" {
  description = "Helm chart version for ingress-nginx."
  type        = string
  default     = "4.11.3"
}

variable "replica_count" {
  description = "Number of NGINX Ingress Controller replicas."
  type        = number
  default     = 2
}

variable "tags" {
  description = "Common tags (not applied to Helm resources directly, for documentation)."
  type        = map(string)
  default     = {}
}
