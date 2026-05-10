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

variable "log_groups" {
  description = "Map of CloudWatch log groups to create, keyed by short name. Each entry defines the log group name (which may interpolate var.cluster_name via the literal placeholder __CLUSTER_NAME__) and an optional per-group retention override. When retention_days is null, var.log_retention_days applies."
  type = map(object({
    name           = string
    retention_days = optional(number)
  }))
  default = {
    eks_application = {
      name = "/aws/eks/__CLUSTER_NAME__/application"
    }
    eks_control_plane = {
      name = "/aws/eks/__CLUSTER_NAME__/cluster"
    }
    lambda_authorizer = {
      name = "/aws/lambda/__CLUSTER_NAME__-authorizer"
    }
    api_gateway = {
      name = "/aws/apigateway/__CLUSTER_NAME__-api"
    }
    jenkins = {
      name = "/aws/ec2/__CLUSTER_NAME__-jenkins"
    }
  }
}
