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
    "ingress-nginx"      = "4.11.3"
    "cluster-autoscaler" = "9.37.0"
    "aws-for-fluent-bit" = "0.1.34"
    "external-secrets"   = "0.10.4"
    "metrics-server"     = "3.12.1"
    "karpenter"          = "1.6.0"
    "jenkins"            = "5.7.16"
    "keda"               = "2.15.2"
  }
}

variable "enable_keda" {
  type    = bool
  default = true
}
