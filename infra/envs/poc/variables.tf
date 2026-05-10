variable "aws_region" {
  description = "AWS region to deploy resources."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name. Combined with the environment (derived from this composition's directory name) to form the master_prefix used for all resource names."
  type        = string
  default     = "max-weather"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for subnet distribution (one per AZ)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ). POC topology uses public subnets for both workers and load balancers."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
}

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.30"
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days (module-wide default; per-group overrides win)."
  type        = number
  default     = 7
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to access the EKS public API endpoint. Set to your operator IP /32."
  type        = list(string)
}

variable "cognito_domain_prefix" {
  description = "Globally unique prefix for the Cognito hosted UI domain (e.g. max-weather-abc123)."
  type        = string
}

###############################################################################
# Module map passthroughs — null means use the module's built-in defaults.
###############################################################################

variable "eks_managed_node_groups" {
  description = "Map of EKS managed node groups passed through to the eks module. Default null preserves the module's single 'general' t3.medium 2/10/2 group."
  type        = any
  default = {
    general = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 10
      desired_size   = 2
      labels         = { role = "general" }
    }
  }
}

variable "eks_managed_node_group_defaults" {
  description = "Defaults applied to every EKS managed node group; per-group overrides win."
  type        = any
  default = {
    attach_cluster_primary_security_group = false
  }
}

variable "cluster_addons" {
  description = "EKS cluster add-ons. Default enables CoreDNS, kube-proxy, VPC CNI, and EKS Pod Identity Agent."
  type        = any
  default = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
  }
}

variable "eks_access_entries" {
  description = "Additional EKS access entries merged after the operator + jenkins entries created by the eks module."
  type        = any
  default     = {}
}

variable "irsa_roles" {
  description = "Map of IRSA roles to create via the iam module. Null (default) ships the five built-in roles: jenkins, cluster-autoscaler, fluent-bit, aws-lb-controller, external-secrets. Override to add custom roles (replaces the defaults — re-declare any built-ins you want kept)."
  type = map(object({
    namespace        = string
    service_account  = string
    policy_json      = string
    role_name_suffix = optional(string)
  }))
  default = null
}

variable "log_groups" {
  description = "Map of CloudWatch log groups to create. Each name may contain the literal __CLUSTER_NAME__ placeholder. Defaults match the prior hardcoded set: eks_application, eks_control_plane, lambda_authorizer, api_gateway, jenkins."
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

variable "ecr_repositories" {
  description = "Map of ECR repositories to create, keyed by full repository name. Repository keys may include the literal placeholder __CLUSTER_NAME__ which the ecr module substitutes with the master_prefix at apply time. Each value carries optional per-repo lifecycle overrides."
  type = map(object({
    image_tag_mutability       = optional(string)
    scan_on_push               = optional(bool)
    keep_tagged_image_count    = optional(number)
    untagged_image_expiry_days = optional(number)
    tag_prefix_list            = optional(list(string), ["staging-", "prod-"])
  }))
  default = {
    "__CLUSTER_NAME__-api"               = {}
    "__CLUSTER_NAME__-lambda-authorizer" = {}
  }
}

variable "secrets" {
  description = "Map of Secrets Manager secrets to create. Each name may contain the literal __CLUSTER_NAME__ placeholder. Defaults match the prior hardcoded set: cognito_client_secret, app_config."
  type = map(object({
    name                    = string
    description             = optional(string)
    initial_value           = optional(string)
    recovery_window_in_days = optional(number, 7)
  }))
  default = {
    cognito_client_secret = {
      name          = "/__CLUSTER_NAME__/cognito/client-secret"
      description   = "Cognito app client secret for weather-api OAuth2."
      initial_value = "PLACEHOLDER_REPLACE_AFTER_COGNITO_APPLY"
    }
    app_config = {
      name          = "/__CLUSTER_NAME__/app/config"
      description   = "weather-api application runtime configuration."
      initial_value = "{\"OPEN_METEO_BASE_URL\":\"https://api.open-meteo.com/v1\",\"PORT\":\"3000\"}"
    }
  }
}

variable "cognito_app_clients" {
  description = "Map of Cognito app clients to create via the cognito module. Defaults ship the single weather_api client (client_credentials M2M flow with read scope)."
  type = map(object({
    name_suffix                          = optional(string)
    generate_secret                      = optional(bool, true)
    allowed_oauth_flows_user_pool_client = optional(bool, true)
    allowed_oauth_flows                  = optional(list(string), ["client_credentials"])
    allowed_oauth_scopes                 = optional(list(string))
    supported_identity_providers         = optional(list(string), ["COGNITO"])
  }))
  default = {
    weather_api = {
      name_suffix = "weather-api"
    }
  }
}
