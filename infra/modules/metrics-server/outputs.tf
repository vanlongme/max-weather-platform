output "release_name" {
  description = "Helm release name."
  value       = helm_release.metrics_server.name
}

output "release_status" {
  description = "Helm release status."
  value       = helm_release.metrics_server.status
}

output "namespace" {
  description = "Deployment namespace."
  value       = helm_release.metrics_server.namespace
}
