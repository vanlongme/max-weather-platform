output "service_role_arns" {
  description = "Map of service-role key to role ARN."
  value       = { for k, r in aws_iam_role.service : k => r.arn }
}

output "service_role_names" {
  description = "Map of service-role key to role name."
  value       = { for k, r in aws_iam_role.service : k => r.name }
}

output "irsa_role_arns" {
  description = "Map of IRSA role key to role ARN. Empty when var.oidc_provider_arn / var.oidc_provider_url are unset."
  value       = { for k, r in aws_iam_role.irsa : k => r.arn }
}

output "irsa_role_names" {
  description = "Map of IRSA role key to role name."
  value       = { for k, r in aws_iam_role.irsa : k => r.name }
}

output "pod_identity_role_arns" {
  description = "Map of Pod Identity role key to role ARN."
  value       = { for k, r in aws_iam_role.pod_identity : k => r.arn }
}

output "pod_identity_role_names" {
  description = "Map of Pod Identity role key to role name."
  value       = { for k, r in aws_iam_role.pod_identity : k => r.name }
}

output "pod_identity_role_bindings" {
  description = "Map of Pod Identity role key to {namespace, service_account, role_arn} — feed straight into the eks module's pod_identity_associations input."
  value = {
    for k, v in local.pod_identity_roles_effective : k => {
      namespace       = v.namespace
      service_account = v.service_account
      role_arn        = aws_iam_role.pod_identity[k].arn
    }
  }
}

output "jenkins_role_arn" {
  description = "Convenience accessor for the Jenkins Pod Identity role ARN. Empty if not present in pod_identity_roles."
  value       = try(aws_iam_role.pod_identity["jenkins"].arn, "")
}

output "jenkins_role_name" {
  description = "Convenience accessor for the Jenkins Pod Identity role name."
  value       = try(aws_iam_role.pod_identity["jenkins"].name, "")
}

output "cluster_autoscaler_role_arn" {
  description = "Convenience accessor for the Cluster Autoscaler Pod Identity role ARN."
  value       = try(aws_iam_role.pod_identity["cluster-autoscaler"].arn, "")
}

output "fluent_bit_role_arn" {
  description = "Convenience accessor for the Fluent Bit Pod Identity role ARN."
  value       = try(aws_iam_role.pod_identity["fluent-bit"].arn, "")
}

output "aws_lb_controller_role_arn" {
  description = "Convenience accessor for the AWS Load Balancer Controller Pod Identity role ARN."
  value       = try(aws_iam_role.pod_identity["aws-lb-controller"].arn, "")
}

output "external_secrets_role_arn" {
  description = "Convenience accessor for the External Secrets Pod Identity role ARN."
  value       = try(aws_iam_role.pod_identity["external-secrets"].arn, "")
}
