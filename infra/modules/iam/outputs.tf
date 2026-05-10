output "irsa_role_arns" {
  description = "Map of IRSA role key to role ARN. Empty during phase 1."
  value       = { for k, r in aws_iam_role.irsa : k => r.arn }
}

output "irsa_role_names" {
  description = "Map of IRSA role key to role name. Empty during phase 1."
  value       = { for k, r in aws_iam_role.irsa : k => r.name }
}

output "jenkins_role_arn" {
  description = "ARN of the Jenkins IRSA role. Empty during phase 1."
  value       = try(aws_iam_role.irsa["jenkins"].arn, "")
}

output "jenkins_role_name" {
  description = "Name of the Jenkins IRSA role. Empty during phase 1."
  value       = try(aws_iam_role.irsa["jenkins"].name, "")
}

output "cluster_autoscaler_role_arn" {
  description = "ARN of the IRSA role for Cluster Autoscaler. Empty during phase 1."
  value       = try(aws_iam_role.irsa["cluster-autoscaler"].arn, "")
}

output "fluent_bit_role_arn" {
  description = "ARN of the IRSA role for Fluent Bit. Empty during phase 1."
  value       = try(aws_iam_role.irsa["fluent-bit"].arn, "")
}

output "aws_lb_controller_role_arn" {
  description = "ARN of the IRSA role for AWS Load Balancer Controller. Empty during phase 1."
  value       = try(aws_iam_role.irsa["aws-lb-controller"].arn, "")
}

output "external_secrets_role_arn" {
  description = "ARN of the IRSA role for External Secrets Operator. Empty during phase 1."
  value       = try(aws_iam_role.irsa["external-secrets"].arn, "")
}
