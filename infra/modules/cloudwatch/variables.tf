variable "cluster_name" {
  description = "EKS cluster name prefix."
  type        = string
}

variable "log_retention_days" {
  description = "Log retention in days."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
