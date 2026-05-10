output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_data" {
  description = "Base64-encoded certificate authority data for the cluster."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_version" {
  description = "Kubernetes version of the cluster."
  value       = module.eks.cluster_version
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster."
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for IRSA."
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider without https:// prefix (used in IRSA trust policies)."
  value       = module.eks.oidc_provider
}

output "cluster_security_group_id" {
  description = "Security group ID of the EKS control plane (managed by EKS)."
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group ID attached to managed node group instances."
  value       = module.eks.node_security_group_id
}

output "karpenter_queue_name" {
  description = "SQS queue name for Karpenter EC2 interruption events."
  value       = module.karpenter.queue_name
}

output "karpenter_node_iam_role_arn" {
  description = "IAM role ARN attached to nodes Karpenter provisions."
  value       = module.karpenter.node_iam_role_arn
}

output "karpenter_node_iam_role_name" {
  description = "IAM role name attached to nodes Karpenter provisions (referenced from EC2NodeClass)."
  value       = module.karpenter.node_iam_role_name
}

output "karpenter_instance_profile_name" {
  description = "Instance profile name attached to nodes Karpenter provisions."
  value       = module.karpenter.instance_profile_name
}
