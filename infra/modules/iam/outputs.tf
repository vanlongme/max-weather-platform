output "eks_cluster_role_arn" {
  description = "ARN of the EKS cluster control-plane IAM role."
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_cluster_role_name" {
  description = "Name of the EKS cluster control-plane IAM role."
  value       = aws_iam_role.eks_cluster.name
}

output "jenkins_role_arn" {
  description = "ARN of the Jenkins EC2 instance role."
  value       = aws_iam_role.jenkins.arn
}

output "jenkins_role_name" {
  description = "Name of the Jenkins EC2 instance role."
  value       = aws_iam_role.jenkins.name
}

output "jenkins_instance_profile_name" {
  description = "Name of the Jenkins EC2 instance profile."
  value       = aws_iam_instance_profile.jenkins.name
}

output "jenkins_instance_profile_arn" {
  description = "ARN of the Jenkins EC2 instance profile."
  value       = aws_iam_instance_profile.jenkins.arn
}

output "eks_node_role_arn" {
  description = "ARN of the EKS node group IAM role."
  value       = aws_iam_role.eks_node.arn
}

output "eks_node_role_name" {
  description = "Name of the EKS node group IAM role."
  value       = aws_iam_role.eks_node.name
}

output "cluster_autoscaler_role_arn" {
  description = "ARN of the IRSA role for Cluster Autoscaler. Empty string if OIDC provider not yet configured."
  value       = try(aws_iam_role.cluster_autoscaler[0].arn, "")
}

output "fluent_bit_role_arn" {
  description = "ARN of the IRSA role for Fluent Bit. Empty string if OIDC provider not yet configured."
  value       = try(aws_iam_role.fluent_bit[0].arn, "")
}

output "aws_lb_controller_role_arn" {
  description = "ARN of the IRSA role for AWS Load Balancer Controller. Empty string if OIDC provider not yet configured."
  value       = try(aws_iam_role.aws_lb_controller[0].arn, "")
}

output "external_secrets_role_arn" {
  description = "ARN of the IRSA role for External Secrets Operator. Empty string if OIDC provider not yet configured."
  value       = try(aws_iam_role.external_secrets[0].arn, "")
}
