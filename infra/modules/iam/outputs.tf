output "jenkins_role_arn" {
  description = "ARN of the Jenkins IRSA role (assumed by the jenkins:jenkins ServiceAccount). Empty during phase 1."
  value       = try(aws_iam_role.jenkins[0].arn, "")
}

output "jenkins_role_name" {
  description = "Name of the Jenkins IRSA role. Empty during phase 1."
  value       = try(aws_iam_role.jenkins[0].name, "")
}

output "cluster_autoscaler_role_arn" {
  description = "ARN of the IRSA role for Cluster Autoscaler (consumed by k8s/helm/cluster-autoscaler)."
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "fluent_bit_role_arn" {
  description = "ARN of the IRSA role for Fluent Bit."
  value       = aws_iam_role.fluent_bit.arn
}

output "aws_lb_controller_role_arn" {
  description = "ARN of the IRSA role for AWS Load Balancer Controller."
  value       = aws_iam_role.aws_lb_controller.arn
}

output "external_secrets_role_arn" {
  description = "ARN of the IRSA role for External Secrets Operator."
  value       = aws_iam_role.external_secrets.arn
}
