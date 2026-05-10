output "release_name" {
  description = "Helm release name for Fluent Bit."
  value       = helm_release.fluent_bit.name
}

output "release_status" {
  description = "Status of the Fluent Bit Helm release."
  value       = helm_release.fluent_bit.status
}
