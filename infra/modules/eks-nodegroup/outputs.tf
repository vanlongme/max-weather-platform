output "node_group_name" {
  description = "Name of the EKS managed node group."
  value       = aws_eks_node_group.main.node_group_name
}

output "node_group_arn" {
  description = "ARN of the EKS managed node group."
  value       = aws_eks_node_group.main.arn
}

output "node_group_status" {
  description = "Status of the EKS managed node group."
  value       = aws_eks_node_group.main.status
}
