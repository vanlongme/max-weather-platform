output "user_pool_id" {
  description = "Cognito User Pool ID."
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN."
  value       = aws_cognito_user_pool.main.arn
}

output "domain" {
  description = "Cognito hosted UI domain prefix."
  value       = aws_cognito_user_pool_domain.main.domain
}

output "token_endpoint" {
  description = "Cognito OAuth2 token endpoint URL."
  value       = "${var.cognito_endpoint_scheme}://${aws_cognito_user_pool_domain.main.domain}${var.cognito_domain_suffix}.${data.aws_region.current.region}.${var.cognito_domain_root}${var.cognito_token_path}"
}

output "jwks_uri" {
  description = "Cognito JWKS URI for JWT validation."
  value       = "${var.cognito_endpoint_scheme}://${var.cognito_idp_domain_prefix}.${data.aws_region.current.region}.${var.aws_dns_suffix}/${aws_cognito_user_pool.main.id}${var.jwks_path}"
}

output "client_ids" {
  description = "Map of app client key to client ID."
  value       = { for k, c in aws_cognito_user_pool_client.app_clients : k => c.id }
}

output "client_secrets" {
  description = "Map of app client key to client secret (sensitive)."
  value       = { for k, c in aws_cognito_user_pool_client.app_clients : k => c.client_secret }
  sensitive   = true
}

output "client_id" {
  description = "Cognito app client ID for the weather-api client (back-compat alias for client_ids[var.primary_client_key])."
  value       = aws_cognito_user_pool_client.app_clients[var.primary_client_key].id
}

output "client_secret" {
  description = "Cognito app client secret for the weather-api client (back-compat alias for client_secrets[var.primary_client_key], sensitive)."
  value       = aws_cognito_user_pool_client.app_clients[var.primary_client_key].client_secret
  sensitive   = true
}

output "resource_server_scope" {
  description = "Full scope string for weather API read access."
  value       = "${var.resource_server_identifier}${var.default_oauth_scope_suffix}"
}
