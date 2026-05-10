variable "name" {
  description = "Name prefix applied to every resource (typically the master_prefix from the composition, e.g. 'poc-max-weather')."
  type        = string
}

variable "cluster_name_placeholder" {
  description = "Literal placeholder token in log group names that is substituted with var.name at apply time."
  type        = string
  default     = "__CLUSTER_NAME__"
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
  description = "Map of CloudWatch log groups to create, keyed by short name. Each entry's optional name field overrides the default <var.name>-<key>-logs naming and may interpolate var.name via the literal placeholder __CLUSTER_NAME__. When name is null the default applies. When retention_days is null, var.log_retention_days applies."
  type = map(object({
    name           = optional(string)
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
