variable "region" {
  description = "AWS region to deploy bootstrap resources."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name used as prefix for resource names."
  type        = string
  default     = "max-weather"
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default = {
    Project     = "max-weather"
    Environment = "bootstrap"
    ManagedBy   = "terraform"
  }
}
