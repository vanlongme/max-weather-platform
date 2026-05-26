variable "cluster_name" {
  description = "EKS cluster name. Used as the discovery tag (karpenter.sh/discovery), subscription target for IRSA-equivalent Pod Identity associations, and identity in Helm release names."
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS API server endpoint URL. Forwarded to in-cluster controllers (Karpenter, cluster-autoscaler) that need to talk to the API server."
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "Base64-encoded EKS cluster CA certificate. Required by in-cluster controllers to verify the API server TLS chain."
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region the cluster is in. Forwarded to controllers (Karpenter, fluent-bit, external-secrets) that need region context for SDK calls and SQS/Logs endpoints."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID the cluster runs in. Reserved for addons that may need direct VPC context (currently unused but retained for forward compatibility)."
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group name fluent-bit ships container logs to. Pre-created by the cloudwatch module so retention/encryption are managed outside the chart."
  type        = string
}

variable "karpenter_queue_name" {
  description = "SQS queue name used by Karpenter to receive EC2 interruption / spot-rebalance events. Provisioned by the eks module; consumed by the karpenter helm release."
  type        = string
}

variable "karpenter_node_iam_role_name" {
  description = "IAM role name attached to Karpenter-provisioned nodes. Templated into the EC2NodeClass spec.role field and referenced in the karpenter helm release values."
  type        = string
}

variable "chart_versions" {
  description = "Helm chart versions for every addon installed by this sub-module. Pinned here so chart upgrades are explicit code changes; override per-chart in tfvars if needed."
  type        = map(string)
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
  description = "Feature flag for the KEDA helm release. Disable when validating cluster bringup with the minimum addon set to isolate failures."
  type        = bool
  default     = true
}

variable "private_subnet_ids" {
  description = "Private subnet IDs Karpenter is allowed to provision workload nodes into. Prevents selection of public subnets that share the canonical kubernetes.io/role/internal-elb tag in a 2-tier VPC."
  type        = list(string)
}
