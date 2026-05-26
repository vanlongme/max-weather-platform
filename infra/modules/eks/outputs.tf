output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_data" {
  description = "Base64-encoded certificate authority data for the cluster."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "Kubernetes version of the cluster."
  value       = aws_eks_cluster.this.version
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "cluster_security_group_id" {
  description = "Security group ID of the EKS control plane (managed by EKS)."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "cluster_kms_key_arn" {
  description = "ARN of the KMS key used for EKS cluster envelope encryption (module-created or caller-supplied via var.existing_cluster_kms_key_arn)."
  value       = local.cluster_kms_key_arn
}

output "ebs_kms_key_arn" {
  description = "ARN of the KMS key used for EBS volume encryption on managed node groups (module-created or caller-supplied via var.existing_ebs_kms_key_arn)."
  value       = local.ebs_kms_key_arn
}

output "cluster_iam_role_arn" {
  description = "ARN of the IAM role attached to the EKS cluster control plane."
  value       = aws_iam_role.cluster.arn
}

output "node_iam_role_arn" {
  description = "ARN of the IAM role attached to managed node group instances."
  value       = aws_iam_role.node.arn
}

output "fargate_iam_role_arn" {
  description = "ARN of the IAM pod execution role used by Fargate profiles."
  value       = aws_iam_role.fargate.arn
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for IRSA."
  value       = length(aws_iam_openid_connect_provider.cluster) > 0 ? aws_iam_openid_connect_provider.cluster[0].arn : null
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider without https:// prefix (used in IRSA trust policies)."
  value       = length(aws_iam_openid_connect_provider.cluster) > 0 ? replace(aws_iam_openid_connect_provider.cluster[0].url, "https://", "") : null
}

output "node_security_group_id" {
  description = "Security group ID attached to managed node group instances."
  value       = aws_security_group.node.id
}

output "node_group_arns" {
  description = "Map of node group ARNs keyed by node group map key."
  value       = { for k, ng in aws_eks_node_group.this : k => ng.arn }
}

output "node_group_names" {
  description = "Map of node group names keyed by node group map key."
  value       = { for k, ng in aws_eks_node_group.this : k => ng.node_group_name }
}

output "fargate_profile_arns" {
  description = "Map of Fargate profile ARNs keyed by profile name."
  value       = { for k, fp in aws_eks_fargate_profile.this : k => fp.arn }
}

output "ebs_csi_controller_role_arn" {
  description = "ARN of the EBS CSI controller IAM role (Pod Identity). Null when enable_ebs_csi_addon = false."
  value       = length(aws_iam_role.ebs_csi_controller) > 0 ? aws_iam_role.ebs_csi_controller[0].arn : null
}

output "efs_csi_controller_role_arn" {
  description = "ARN of the EFS CSI controller IAM role (Pod Identity). Null when enable_efs_csi_addon = false."
  value       = length(aws_iam_role.efs_csi_controller) > 0 ? aws_iam_role.efs_csi_controller[0].arn : null
}

output "karpenter_queue_name" {
  description = "Name of the Karpenter SQS interruption queue."
  value       = aws_sqs_queue.karpenter.name
}

output "karpenter_node_iam_role_arn" {
  description = "ARN of the IAM role assumed by Karpenter-provisioned EC2 nodes."
  value       = aws_iam_role.karpenter_node.arn
}

output "karpenter_node_iam_role_name" {
  description = "Name of the IAM role assumed by Karpenter-provisioned EC2 nodes."
  value       = aws_iam_role.karpenter_node.name
}

output "karpenter_instance_profile_name" {
  description = "Name of the IAM instance profile attached to Karpenter-provisioned nodes. Null when karpenter_create_instance_profile = false."
  value       = length(aws_iam_instance_profile.karpenter_node) > 0 ? aws_iam_instance_profile.karpenter_node[0].name : null
}
