output "release_name" {
  description = "Helm release name for AWS Load Balancer Controller."
  value       = helm_release.aws_lb_controller.name
}

output "release_status" {
  description = "Status of the AWS Load Balancer Controller Helm release."
  value       = helm_release.aws_lb_controller.status
}
