output "release_name" {
  description = "Helm release name for Cluster Autoscaler."
  value       = helm_release.cluster_autoscaler.name
}

output "release_status" {
  description = "Status of the Cluster Autoscaler Helm release."
  value       = helm_release.cluster_autoscaler.status
}
