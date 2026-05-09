variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-1"
}

variable "enable_irsa" {
  description = "Enable IRSA roles (Phase 2 — set true AFTER EKS cluster is applied in Phase 1)"
  type        = bool
  default     = false
}

variable "weatherapi_key" {
  description = "WeatherAPI.com API key — stored in Secrets Manager via secrets module"
  type        = string
  sensitive   = true
}

variable "test_user_email" {
  description = "Cognito test user email for automated testing"
  type        = string
  default     = "testuser@maxweather.io"
}

variable "test_user_password" {
  description = "Cognito test user password (sensitive)"
  type        = string
  sensitive   = true
  default     = "TempPassword!23"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "max-weather-cluster"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS managed node group"
  type        = string
  default     = "t3.medium"
}
