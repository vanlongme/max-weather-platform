variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "VPC ID where the cluster lives."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for managed node groups and control plane ENIs. POC topology passes the public subnet IDs here; production should pass private subnet IDs."
  type        = list(string)
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint."
  type        = list(string)

  validation {
    condition     = !contains(var.allowed_cidrs, "0.0.0.0/0")
    error_message = "allowed_cidrs must not include 0.0.0.0/0. Restrict to your operator IP CIDR."
  }
}

variable "operator_principal_arn" {
  description = "IAM principal ARN granted cluster-admin via access entry."
  type        = string
}

variable "jenkins_role_arn" {
  description = "Jenkins IRSA role ARN granted namespace-scoped Edit access on var.jenkins_access_namespaces. Empty during phase 1 (before IAM module creates the IRSA role); the access entry is omitted when empty."
  type        = string
  default     = ""
}

variable "jenkins_access_namespaces" {
  description = "Kubernetes namespaces on which the Jenkins IRSA role is granted Edit access via the EKS access entry. Defaults to the weather-api app namespaces; override for other projects."
  type        = list(string)
  default     = ["weather-staging", "weather-prod"]
}

variable "eks_managed_node_groups" {
  description = "Map of EKS managed node group definitions, keyed by node group name. Each entry is passed through to the upstream eks_managed_node_groups input."
  type = map(object({
    name           = optional(string)
    instance_types = optional(list(string), ["t3.medium"])
    min_size       = optional(number, 2)
    max_size       = optional(number, 10)
    desired_size   = optional(number, 2)
    capacity_type  = optional(string, "ON_DEMAND")
    ami_type       = optional(string, "AL2023_x86_64_STANDARD")
    disk_size      = optional(number, 20)
    labels         = optional(map(string), {})
    taints         = optional(map(object({ key = string, value = optional(string), effect = string })), {})
    tags           = optional(map(string), {})
  }))
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
  description = "Defaults applied to every managed node group. Per-group overrides win. enable_monitoring and use_latest_ami_release_version are pinned here to preserve v20 behavior after the v21 default flips (true->false and false->true respectively)."
  type        = any
  default = {
    attach_cluster_primary_security_group = false
    enable_monitoring                     = true
    use_latest_ami_release_version        = false
  }
}

variable "cluster_addons" {
  description = "Map of EKS add-ons to enable. Passed through to the upstream addons input (renamed from cluster_addons in v21). resolve_conflicts_on_create=OVERWRITE and most_recent=false are pinned per-addon to preserve v20 behavior after the v21 default flips."
  type        = any
  default = {
    coredns = {
      resolve_conflicts_on_create = "OVERWRITE"
      most_recent                 = false
    }
    kube-proxy = {
      resolve_conflicts_on_create = "OVERWRITE"
      most_recent                 = false
    }
    vpc-cni = {
      before_compute              = true
      resolve_conflicts_on_create = "OVERWRITE"
      most_recent                 = false
    }
    eks-pod-identity-agent = {
      before_compute              = true
      resolve_conflicts_on_create = "OVERWRITE"
      most_recent                 = false
    }
  }
}

variable "access_entries" {
  description = "Additional access entries merged after operator + jenkins entries derived from operator_principal_arn / jenkins_role_arn. User-supplied entries win on key collision."
  type        = any
  default     = {}
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "endpoint_public_access" {
  description = "Whether the EKS API server endpoint is reachable from the public internet (restricted further by var.allowed_cidrs)."
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  description = "Whether the EKS API server endpoint is reachable from inside the VPC."
  type        = bool
  default     = true
}

variable "enabled_log_types" {
  description = "EKS control-plane log types to ship to CloudWatch Logs."
  type        = list(string)
  default = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]
}

variable "enable_irsa" {
  description = "Whether to create the OIDC provider required by IAM Roles for Service Accounts."
  type        = bool
  default     = true
}

variable "authentication_mode" {
  description = "EKS access mode. API_AND_CONFIG_MAP keeps the legacy aws-auth ConfigMap available alongside access entries."
  type        = string
  default     = "API_AND_CONFIG_MAP"
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Whether the IAM principal that runs `terraform apply` is auto-granted cluster-admin via an implicit access entry. Disabled so the explicit operator access entry is the single source of truth."
  type        = bool
  default     = false
}

variable "operator_access_entry_key" {
  description = "Map key for the operator access entry inside the access_entries map."
  type        = string
  default     = "operator"
}

variable "operator_policy_association_key" {
  description = "Map key for the policy association under the operator access entry."
  type        = string
  default     = "admin"
}

variable "operator_cluster_access_policy_arn_template" {
  description = "ARN template for the cluster-admin EKS cluster access policy. The literal var.partition_placeholder is substituted with data.aws_partition.current.partition."
  type        = string
  default     = "arn:__AWS_PARTITION__:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
}

variable "operator_access_scope_type" {
  description = "Access scope type for the operator policy association (cluster-wide admin)."
  type        = string
  default     = "cluster"
}

variable "jenkins_access_entry_key" {
  description = "Map key for the jenkins access entry inside the access_entries map."
  type        = string
  default     = "jenkins"
}

variable "jenkins_policy_association_key" {
  description = "Map key for the policy association under the jenkins access entry."
  type        = string
  default     = "edit"
}

variable "jenkins_cluster_access_policy_arn_template" {
  description = "ARN template for the namespace-scoped Edit EKS cluster access policy. The literal var.partition_placeholder is substituted with data.aws_partition.current.partition."
  type        = string
  default     = "arn:__AWS_PARTITION__:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
}

variable "jenkins_access_scope_type" {
  description = "Access scope type for the jenkins policy association (namespace-scoped Edit)."
  type        = string
  default     = "namespace"
}

variable "partition_placeholder" {
  description = "Literal placeholder token in cluster access policy ARN templates substituted with data.aws_partition.current.partition at apply time."
  type        = string
  default     = "__AWS_PARTITION__"
}

variable "node_group_name_separator" {
  description = "Separator placed between var.cluster_name and the node-group map key when synthesizing the upstream `name` argument."
  type        = string
  default     = "-"
}

variable "cluster_autoscaler_enabled_tag_key" {
  description = "Node group tag key signalling that Cluster Autoscaler should consider this ASG."
  type        = string
  default     = "k8s.io/cluster-autoscaler/enabled"
}

variable "cluster_autoscaler_enabled_tag_value" {
  description = "Node group tag value for the Cluster Autoscaler enabled tag."
  type        = string
  default     = "true"
}

variable "cluster_autoscaler_owned_tag_key_prefix" {
  description = "Prefix for the per-cluster Cluster Autoscaler ownership tag. The cluster name is appended to form the full key (k8s.io/cluster-autoscaler/<cluster_name>)."
  type        = string
  default     = "k8s.io/cluster-autoscaler/"
}

variable "cluster_autoscaler_owned_tag_value" {
  description = "Tag value applied to k8s.io/cluster-autoscaler/<cluster_name> on managed node group ASGs."
  type        = string
  default     = "owned"
}

variable "karpenter_discovery_tag_key" {
  description = "Tag key consumed by Karpenter EC2NodeClass.securityGroupSelectorTerms / subnetSelectorTerms (and applied to karpenter sub-module resources)."
  type        = string
  default     = "karpenter.sh/discovery"
}

variable "karpenter_create_pod_identity_association" {
  description = "Whether the upstream karpenter sub-module should create an EKS Pod Identity association for the controller IAM role."
  type        = bool
  default     = true
}

variable "karpenter_create_instance_profile" {
  description = "Whether the upstream karpenter sub-module should create the EC2 instance profile attached to Karpenter-provisioned nodes."
  type        = bool
  default     = true
}

variable "karpenter_iam_role_name_suffix" {
  description = "Suffix appended to var.cluster_name to form the karpenter controller IAM role and policy name."
  type        = string
  default     = "-karpenter-controller"
}

variable "karpenter_iam_role_use_name_prefix" {
  description = "Whether the upstream karpenter sub-module treats iam_role_name as a name_prefix instead of a fixed name."
  type        = bool
  default     = false
}

variable "karpenter_iam_policy_use_name_prefix" {
  description = "Whether the upstream karpenter sub-module treats iam_policy_name as a name_prefix instead of a fixed name."
  type        = bool
  default     = false
}

variable "karpenter_node_iam_role_name_suffix" {
  description = "Suffix appended to var.cluster_name to form the karpenter node IAM role name."
  type        = string
  default     = "-karpenter-node"
}

variable "karpenter_node_iam_role_use_name_prefix" {
  description = "Whether the upstream karpenter sub-module treats node_iam_role_name as a name_prefix instead of a fixed name."
  type        = bool
  default     = false
}

variable "karpenter_queue_name_suffix" {
  description = "Suffix appended to var.cluster_name to form the karpenter SQS queue name (receives EC2 spot interruption / health events)."
  type        = string
  default     = "-karpenter"
}

variable "karpenter_node_additional_policies" {
  description = "Additional managed-policy ARNs (keyed by short name) attached to the karpenter node IAM role. The literal var.partition_placeholder is substituted with data.aws_partition.current.partition at apply time. Default: SSM Session Manager access."
  type        = map(string)
  default = {
    AmazonSSMManagedInstanceCore = "arn:__AWS_PARTITION__:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

