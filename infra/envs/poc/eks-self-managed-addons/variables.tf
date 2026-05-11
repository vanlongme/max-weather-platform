variable "cluster_name" {
  type = string
}

variable "cluster_endpoint" {
  type = string
}

variable "cluster_certificate_authority_data" {
  type      = string
  sensitive = true
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "log_group_name" {
  type = string
}

variable "karpenter_queue_name" {
  type = string
}

variable "karpenter_node_iam_role_name" {
  type = string
}

variable "chart_versions" {
  type = map(string)
  default = {
    "ingress-nginx"      = "4.15.1"
    "cluster-autoscaler" = "9.57.0"
    "fluent-bit"         = "0.57.3"
    "external-secrets"   = "2.4.1"
    "metrics-server"     = "3.13.0"
    "karpenter"          = "1.12.0"
    "jenkins"            = "5.9.18"
    "keda"               = "2.19.0"
  }
}

variable "enable_keda" {
  type    = bool
  default = true
}
