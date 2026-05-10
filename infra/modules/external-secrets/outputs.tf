output "release_name" {
  description = "Helm release name for External Secrets Operator."
  value       = helm_release.external_secrets.name
}

output "release_status" {
  description = "Status of the External Secrets Operator Helm release."
  value       = helm_release.external_secrets.status
}

output "cluster_secret_store_name" {
  description = "Name of the ClusterSecretStore resource."
  value       = "aws-secretsmanager"
}
