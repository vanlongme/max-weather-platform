output "vpc_id" {
  description = "VPC ID."
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.networking.private_subnet_ids
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint."
  value       = module.eks_cluster.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider."
  value       = module.eks_cluster.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "URL of the EKS OIDC provider (without https://)."
  value       = module.eks_cluster.oidc_provider_url
}

output "ecr_api_repository_url" {
  description = "ECR URL for the weather API image."
  value       = module.ecr.repository_urls["${var.cluster_name}-api"]
}

output "ecr_lambda_repository_url" {
  description = "ECR URL for the Lambda authorizer image."
  value       = module.ecr.repository_urls["${var.cluster_name}-lambda-authorizer"]
}

output "cognito_client_id" {
  description = "Cognito app client ID."
  value       = module.cognito.client_id
}

output "cognito_token_endpoint" {
  description = "Cognito OAuth2 token endpoint."
  value       = module.cognito.token_endpoint
}

output "cognito_jwks_uri" {
  description = "Cognito JWKS URI for JWT validation."
  value       = module.cognito.jwks_uri
}
