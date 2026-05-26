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
  description = "Map of Pod Identity role key to {namespace, service_account, role_arn} — feed straight into the eks module's pod_identity_associations input. CSI driver keys are excluded because their Pod Identity associations are created by the per-addon `pod_identity_association` block on `module.eks` cluster_addons, not by the cluster-level pod_identity_associations input."
  value = {
    for k, v in local.pod_identity_roles_effective : k => {
      namespace       = v.namespace
      service_account = v.service_account
      role_arn        = aws_iam_role.pod_identity[k].arn
    } if !contains(["ebs-csi-controller", "efs-csi-controller"], k)
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

output "external_secrets_role_arn" {
  description = "Convenience accessor for the External Secrets Pod Identity role ARN."
  value       = try(aws_iam_role.pod_identity["external-secrets"].arn, "")
}

output "ebs_csi_controller_role_arn" {
  description = "Convenience accessor for the EBS CSI controller Pod Identity role ARN."
  value       = try(aws_iam_role.pod_identity["ebs-csi-controller"].arn, "")
}

output "efs_csi_controller_role_arn" {
  description = "Convenience accessor for the EFS CSI controller Pod Identity role ARN."
  value       = try(aws_iam_role.pod_identity["efs-csi-controller"].arn, "")
}

output "lambda_authorizer_role_arn" {
  description = "Convenience accessor for the Lambda Authorizer service role ARN. Empty if not present in service_roles."
  value       = try(aws_iam_role.service["lambda_authorizer"].arn, "")
}

output "lambda_authorizer_role_name" {
  description = "Convenience accessor for the Lambda Authorizer service role name."
  value       = try(aws_iam_role.service["lambda_authorizer"].name, "")
}

output "cosign_key_alias" {
  description = "KMS alias for the cosign image signing key. Use awskms:///alias/max-weather-cosign-signer in cosign CLI."
  value       = aws_kms_alias.cosign_signer.name
}

output "cosign_key_arn" {
  description = "ARN of the KMS ECC signing key used by cosign."
  value       = aws_kms_key.cosign_signer.arn
}
