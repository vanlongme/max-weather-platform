output "ingress_nginx_namespace" {
  value = helm_release.ingress_nginx.namespace
}

output "karpenter_namespace" {
  value = helm_release.karpenter.namespace
}

output "keda_namespace" {
  value = var.enable_keda ? helm_release.keda[0].namespace : null
}
