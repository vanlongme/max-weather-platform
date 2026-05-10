output "release_name" {
  description = "Helm release name for NGINX Ingress Controller."
  value       = helm_release.nginx_ingress.name
}

output "release_status" {
  description = "Status of the NGINX Ingress Helm release."
  value       = helm_release.nginx_ingress.status
}

output "namespace" {
  description = "Namespace where NGINX Ingress Controller is deployed."
  value       = helm_release.nginx_ingress.namespace
}
