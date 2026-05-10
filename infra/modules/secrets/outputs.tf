output "secret_arns" {
  description = "Map of secret key to secret ARN."
  value       = { for k, s in aws_secretsmanager_secret.secrets : k => s.arn }
}

output "secret_names" {
  description = "Map of secret key to secret name."
  value       = { for k, s in aws_secretsmanager_secret.secrets : k => s.name }
}

output "cognito_client_secret_arn" {
  description = "ARN of the Cognito client secret in Secrets Manager."
  value       = aws_secretsmanager_secret.secrets["cognito_client_secret"].arn
}

output "cognito_client_secret_name" {
  description = "Name of the Cognito client secret."
  value       = aws_secretsmanager_secret.secrets["cognito_client_secret"].name
}

output "app_config_secret_arn" {
  description = "ARN of the app config secret."
  value       = aws_secretsmanager_secret.secrets["app_config"].arn
}

output "app_config_secret_name" {
  description = "Name of the app config secret."
  value       = aws_secretsmanager_secret.secrets["app_config"].name
}
