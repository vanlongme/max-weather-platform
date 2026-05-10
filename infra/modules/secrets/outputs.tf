output "cognito_client_secret_arn" {
  description = "ARN of the Cognito client secret in Secrets Manager."
  value       = aws_secretsmanager_secret.cognito_client_secret.arn
}

output "cognito_client_secret_name" {
  description = "Name of the Cognito client secret."
  value       = aws_secretsmanager_secret.cognito_client_secret.name
}

output "app_config_secret_arn" {
  description = "ARN of the app config secret."
  value       = aws_secretsmanager_secret.app_config.arn
}

output "app_config_secret_name" {
  description = "Name of the app config secret."
  value       = aws_secretsmanager_secret.app_config.name
}
