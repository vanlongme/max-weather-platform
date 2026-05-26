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
  default     = "1.34"
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

###############################################################################
# Module map passthroughs — null means use the module's built-in defaults.
###############################################################################

variable "eks_managed_node_groups" {
  description = "Map of EKS managed node groups passed through to the eks module. Default ships a single 'infra' Bottlerocket t3.medium 1/10/1 group tainted role=infra:NoSchedule; cluster addon controllers tolerate it, workload pods land on Karpenter-provisioned nodes instead."
  type        = any
  default = {
    infra = {
      instance_types = ["t3.medium"]
      ami_type       = "BOTTLEROCKET_x86_64"
      min_size       = 1
      max_size       = 10
      desired_size   = 1
      labels         = { role = "infra" }
      taints = {
        infra = { key = "role", value = "infra", effect = "NO_SCHEDULE" }
      }
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
  description = "EKS cluster add-ons surfaced as `aws_eks_addon` resources by the eks module. Default ships CoreDNS, kube-proxy, VPC CNI, and EKS Pod Identity Agent. EBS/EFS CSI drivers are owned by the eks module itself (enable_ebs_csi_addon / enable_efs_csi_addon) — do not declare them here."
  type        = any
  default = {
    coredns = {
      configuration_values = "{\"tolerations\":[{\"key\":\"role\",\"operator\":\"Equal\",\"value\":\"infra\",\"effect\":\"NoSchedule\"}]}"
    }
    kube-proxy             = { depends_on_node_group = true }
    vpc-cni                = { depends_on_node_group = false }
    eks-pod-identity-agent = { depends_on_node_group = true }
  }
}

variable "eks_access_entries" {
  description = "Additional EKS access entries merged after the operator + jenkins entries created by the eks module."
  type        = any
  default     = {}
}

variable "pod_identity_roles" {
  description = "Map of EKS Pod Identity roles to create via the iam module (pods.eks.amazonaws.com trust). Default ships the five non-CSI workload roles: jenkins, jenkins-agent, cluster-autoscaler, fluent-bit, external-secrets. CSI controller roles (ebs-csi-controller, efs-csi-controller) are owned by the eks module itself. Override to add custom roles (replaces the defaults — re-declare any built-ins you want kept)."
  type = map(object({
    namespace           = string
    service_account     = string
    policy_json         = string
    role_name_suffix    = optional(string)
    managed_policy_arns = optional(list(string), [])
  }))
  default = {
    jenkins = {
      namespace        = "jenkins"
      service_account  = "jenkins"
      role_name_suffix = "jenkins"
      policy_json      = <<-EOT
         {
           "Version": "2012-10-17",
           "Statement": [
             {
               "Sid": "ECRAccess",
               "Effect": "Allow",
               "Action": [
                 "ecr:GetAuthorizationToken",
                 "ecr:BatchCheckLayerAvailability",
                 "ecr:GetDownloadUrlForLayer",
                 "ecr:BatchGetImage",
                 "ecr:PutImage",
                 "ecr:InitiateLayerUpload",
                 "ecr:UploadLayerPart",
                 "ecr:CompleteLayerUpload",
                 "ecr:DescribeRepositories",
                 "ecr:DescribeImages",
                 "ecr:ListImages"
               ],
               "Resource": "*"
             },
             {
               "Sid": "EKSAccess",
               "Effect": "Allow",
               "Action": [
                 "eks:DescribeCluster",
                 "eks:ListClusters"
               ],
               "Resource": "*"
             },
             {
               "Sid": "LambdaDeployAccess",
               "Effect": "Allow",
               "Action": [
                 "lambda:UpdateFunctionCode",
                 "lambda:GetFunction"
               ],
               "Resource": "arn:__AWS_PARTITION__:lambda:__AWS_REGION__:__AWS_ACCOUNT_ID__:function:__CLUSTER_NAME__-*"
             },
             {
               "Sid": "CloudWatchLogs",
               "Effect": "Allow",
               "Action": [
                 "logs:CreateLogGroup",
                 "logs:CreateLogStream",
                 "logs:PutLogEvents",
                 "logs:DescribeLogGroups"
               ],
               "Resource": "*"
             }
           ]
         }
         EOT
    }
    jenkins-agent = {
      namespace        = "jenkins"
      service_account  = "jenkins-agent"
      role_name_suffix = "jenkins-agent"
      policy_json      = <<-EOT
         {
           "Version": "2012-10-17",
           "Statement": [
             {
               "Sid": "ECRAccess",
               "Effect": "Allow",
               "Action": [
                 "ecr:GetAuthorizationToken",
                 "ecr:BatchCheckLayerAvailability",
                 "ecr:GetDownloadUrlForLayer",
                 "ecr:BatchGetImage",
                 "ecr:PutImage",
                 "ecr:InitiateLayerUpload",
                 "ecr:UploadLayerPart",
                 "ecr:CompleteLayerUpload",
                 "ecr:DescribeRepositories",
                 "ecr:DescribeImages",
                 "ecr:ListImages"
               ],
               "Resource": "*"
             },
             {
               "Sid": "EKSAccess",
               "Effect": "Allow",
               "Action": [
                 "eks:DescribeCluster",
                 "eks:ListClusters"
               ],
               "Resource": "*"
             },
             {
               "Sid": "LambdaDeployAccess",
               "Effect": "Allow",
               "Action": [
                 "lambda:UpdateFunctionCode",
                 "lambda:GetFunction"
               ],
               "Resource": "arn:__AWS_PARTITION__:lambda:__AWS_REGION__:__AWS_ACCOUNT_ID__:function:__CLUSTER_NAME__-*"
             },
             {
               "Sid": "CloudWatchLogs",
               "Effect": "Allow",
               "Action": [
                 "logs:CreateLogGroup",
                 "logs:CreateLogStream",
                 "logs:PutLogEvents",
                 "logs:DescribeLogGroups"
               ],
               "Resource": "*"
             }
           ]
         }
         EOT
    }
    cluster-autoscaler = {
      namespace        = "kube-system"
      service_account  = "cluster-autoscaler"
      role_name_suffix = "cluster-autoscaler"
      policy_json      = <<-EOT
         {
           "Version": "2012-10-17",
           "Statement": [
             {
               "Effect": "Allow",
               "Action": [
                 "autoscaling:DescribeAutoScalingGroups",
                 "autoscaling:DescribeAutoScalingInstances",
                 "autoscaling:DescribeLaunchConfigurations",
                 "autoscaling:DescribeScalingActivities",
                 "autoscaling:DescribeTags",
                 "ec2:DescribeInstanceTypes",
                 "ec2:DescribeLaunchTemplateVersions",
                 "ec2:DescribeImages",
                 "ec2:GetInstanceTypesFromInstanceRequirements",
                 "eks:DescribeNodegroup"
               ],
               "Resource": "*"
             },
             {
               "Effect": "Allow",
               "Action": [
                 "autoscaling:SetDesiredCapacity",
                 "autoscaling:TerminateInstanceInAutoScalingGroup"
               ],
               "Resource": "*"
             }
           ]
         }
         EOT
    }
    fluent-bit = {
      namespace        = "amazon-cloudwatch"
      service_account  = "fluent-bit"
      role_name_suffix = "fluent-bit"
      policy_json      = <<-EOT
         {
           "Version": "2012-10-17",
           "Statement": [
             {
               "Effect": "Allow",
               "Action": [
                 "logs:CreateLogGroup",
                 "logs:CreateLogStream",
                 "logs:PutLogEvents",
                 "logs:DescribeLogGroups",
                 "logs:DescribeLogStreams",
                 "logs:PutRetentionPolicy"
               ],
               "Resource": "*"
             }
           ]
         }
         EOT
    }
    external-secrets = {
      namespace        = "external-secrets"
      service_account  = "external-secrets"
      role_name_suffix = "external-secrets"
      policy_json      = <<-EOT
         {
           "Version": "2012-10-17",
           "Statement": [
             {
               "Effect": "Allow",
               "Action": [
                 "secretsmanager:GetSecretValue",
                 "secretsmanager:DescribeSecret",
                 "secretsmanager:ListSecrets"
               ],
               "Resource": "*"
             },
             {
               "Effect": "Allow",
               "Action": [
                 "ssm:GetParameter",
                 "ssm:GetParameters",
                 "ssm:GetParametersByPath",
                 "ssm:DescribeParameters"
               ],
               "Resource": "*"
             }
           ]
         }
         EOT
    }
  }
}

variable "iam_service_roles" {
  description = "Map of AWS service-principal IAM roles to create via the iam module (e.g. Lambda execution roles, EC2 instance roles). Default ships the lambda_authorizer execution role (Secrets Manager scoped to the authorizer JWT secret)."
  type = map(object({
    service_principals  = list(string)
    policy_json         = optional(string)
    managed_policy_arns = optional(list(string), [])
    role_name_suffix    = optional(string)
  }))
  default = {
    lambda_authorizer = {
      service_principals  = ["lambda.amazonaws.com"]
      managed_policy_arns = ["arn:__AWS_PARTITION__:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
      policy_json         = <<-EOT
        {
          "Version": "2012-10-17",
          "Statement": [
            {
              "Sid": "AllowGetSecret",
              "Effect": "Allow",
              "Action": "secretsmanager:GetSecretValue",
               "Resource": "arn:__AWS_PARTITION__:secretsmanager:__AWS_REGION__:__AWS_ACCOUNT_ID__:secret:__CLUSTER_NAME__-authorizer-jwt-*"
            }
          ]
        }
      EOT
    }
  }
}

variable "iam_irsa_roles" {
  description = "Map of legacy IRSA (OIDC web-identity) roles to create via the iam module. Empty by default — prefer pod_identity_roles for new workloads."
  type = map(object({
    namespace        = string
    service_account  = string
    policy_json      = string
    role_name_suffix = optional(string)
  }))
  default = {}
}

variable "log_groups" {
  description = "Map of CloudWatch log groups to create. Each name may contain the literal __CLUSTER_NAME__ placeholder. Defaults: eks_application, eks_control_plane, api_gateway, jenkins. Note: lambda_authorizer LG is created by the lambda module (not here)."
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
    api = {}
  }
}

variable "secrets" {
  description = "Map of Secrets Manager secrets to create. Each name may contain the literal __CLUSTER_NAME__ placeholder. Defaults: authorizer_jwt_secret (HS256 signing key) and app_config."
  type = map(object({
    name                    = string
    description             = optional(string)
    initial_value           = optional(string)
    recovery_window_in_days = optional(number, 7)
  }))
  default = {
    authorizer_jwt_secret = {
      name                    = "__CLUSTER_NAME__-authorizer-jwt-secret"
      description             = "HS256 shared secret for the Lambda authorizer (operator-populated post-apply)."
      initial_value           = "CHANGE-ME-32-BYTE-SECRET-AT-LEAST"
      recovery_window_in_days = 0
    }
    app_config = {
      name          = "/__CLUSTER_NAME__/app/config"
      description   = "weather-api application runtime configuration."
      initial_value = "{\"OPEN_METEO_BASE_URL\":\"https://api.open-meteo.com/v1\"}"
    }
    authorizer_jwt_secret_prod = {
      name                    = "__CLUSTER_NAME__-authorizer-jwt-secret-prod"
      description             = "HS256 JWT signing secret for the prod API Gateway stage (operator-populated post-apply)."
      recovery_window_in_days = 0
    }
  }
}

variable "lambda_functions" {
  description = "Map of Lambda functions to deploy via the lambda module. Supplying this map REPLACES the default entirely (no merge). Default ships the authorizer function wired to the iam module's lambda_authorizer_role_arn and the secrets module's authorizer_jwt_secret_arn."
  type = map(object({
    source_dir           = string
    handler              = string
    runtime              = optional(string, "nodejs22.x")
    memory_size          = optional(number, 128)
    timeout              = optional(number, 5)
    environment          = optional(map(string), {})
    log_retention_days   = optional(number, 14)
    function_name_suffix = optional(string, "")
    role_arn             = string
    invoke_principals    = optional(map(string), {})
    npm_install_dir      = optional(string, null)
  }))
  default = {}
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ). Used for EKS workload nodes and Karpenter-provisioned nodes."
  type        = list(string)
  default     = ["10.20.11.0/24", "10.20.12.0/24", "10.20.13.0/24"]
}

variable "enable_nat_gateway" {
  description = "Whether to create a NAT Gateway for private subnet egress. Single NAT in AZ-a (AZ-a failure breaks egress — accepted for POC)."
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Whether to create VPC interface endpoints. Enables private AWS API access without traversing the public internet."
  type        = bool
  default     = true
}

variable "enable_s3_gateway_endpoint" {
  description = "Whether to create an S3 gateway endpoint. Reduces NAT Gateway data transfer costs for S3 traffic (ECR layer pulls, tfstate)."
  type        = bool
  default     = true
}

variable "vpc_endpoint_private_dns_enabled" {
  description = "Whether to enable private DNS for VPC interface endpoints. Required for SDK/CLI clients to resolve AWS service hostnames to private IPs."
  type        = bool
  default     = true
}

variable "vpc_interface_endpoints" {
  description = "List of AWS service names for VPC interface endpoints. Comprehensive set covers all services used by EKS workloads."
  type        = list(string)
  default = [
    "ec2",
    "ecr.api",
    "ecr.dkr",
    "sts",
    "logs",
    "eks",
    "eks-auth",
    "ssm",
    "ssmmessages",
    "ec2messages",
    "secretsmanager",
    "kms",
    "autoscaling",
    "elasticloadbalancing",
    "lambda",
    "monitoring",
  ]
}

variable "endpoint_private_access" {
  description = "Whether the EKS API server endpoint is reachable from inside the VPC via the private endpoint."
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Whether the EKS API server endpoint is reachable from the public internet (restricted further by allowed_cidrs). Kept true for hybrid POC posture; fully-private deferred to manual hardening."
  type        = bool
  default     = true
}

variable "enabled_log_types" {
  description = "EKS control-plane log types to ship to CloudWatch Logs. All 5 types enabled for security hardening and audit."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}
