variable "cluster_name" {
  description = "EKS cluster name prefix."
  type        = string
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
