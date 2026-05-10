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
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/token"
}

output "jwks_uri" {
  description = "Cognito JWKS URI for JWT validation."
  value       = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.main.id}/.well-known/jwks.json"
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
  description = "Cognito app client ID for the weather-api client (back-compat alias for client_ids[\"weather_api\"])."
  value       = aws_cognito_user_pool_client.app_clients["weather_api"].id
}

output "client_secret" {
  description = "Cognito app client secret for the weather-api client (back-compat alias for client_secrets[\"weather_api\"], sensitive)."
  value       = aws_cognito_user_pool_client.app_clients["weather_api"].client_secret
  sensitive   = true
}

output "resource_server_scope" {
  description = "Full scope string for weather API read access."
  value       = "${var.resource_server_identifier}/read"
}
