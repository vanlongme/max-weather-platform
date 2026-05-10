output "repository_urls" {
  description = "Map of repository name to repository URL (for docker push/pull)."
  value       = { for name, repo in aws_ecr_repository.repos : name => repo.repository_url }
}

output "repository_arns" {
  description = "Map of repository name to repository ARN."
  value       = { for name, repo in aws_ecr_repository.repos : name => repo.arn }
}

output "repository_names" {
  description = "List of repository names that were created."
  value       = [for repo in aws_ecr_repository.repos : repo.name]
}

output "registry_ids" {
  description = "Map of repository name to registry ID (AWS account ID hosting the registry)."
  value       = { for name, repo in aws_ecr_repository.repos : name => repo.registry_id }
}
