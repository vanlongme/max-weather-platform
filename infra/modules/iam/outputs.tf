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
