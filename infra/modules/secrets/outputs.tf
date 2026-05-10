output "secret_arns" {
  description = "Map of secret key to secret ARN."
  value       = { for k, s in aws_secretsmanager_secret.secrets : k => s.arn }
}

output "secret_names" {
  description = "Map of secret key to secret name."
  value       = { for k, s in aws_secretsmanager_secret.secrets : k => s.name }
}

output "authorizer_jwt_secret_arn" {
  description = "ARN of the Lambda authorizer JWT signing secret in Secrets Manager."
  value       = aws_secretsmanager_secret.secrets["authorizer_jwt_secret"].arn
}

output "authorizer_jwt_secret_name" {
  description = "Name of the Lambda authorizer JWT signing secret."
  value       = aws_secretsmanager_secret.secrets["authorizer_jwt_secret"].name
}

output "app_config_secret_arn" {
  description = "ARN of the app config secret."
  value       = aws_secretsmanager_secret.secrets["app_config"].arn
}

output "app_config_secret_name" {
  description = "Name of the app config secret."
  value       = aws_secretsmanager_secret.secrets["app_config"].name
}
