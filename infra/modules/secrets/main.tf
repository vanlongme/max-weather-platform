resource "aws_secretsmanager_secret" "cognito_client_secret" {
  name                    = "/${var.cluster_name}/cognito/client-secret"
  description             = "Cognito app client secret for weather-api OAuth2."
  recovery_window_in_days = 7
  tags                    = merge(var.tags, { Name = "${var.cluster_name}-cognito-client-secret" })
}

resource "aws_secretsmanager_secret_version" "cognito_client_secret" {
  secret_id     = aws_secretsmanager_secret.cognito_client_secret.id
  secret_string = "PLACEHOLDER_REPLACE_AFTER_COGNITO_APPLY"
  lifecycle {
    ignore_changes = [secret_string] # managed externally after Cognito apply
  }
}

resource "aws_secretsmanager_secret" "app_config" {
  name                    = "/${var.cluster_name}/app/config"
  description             = "weather-api application runtime configuration."
  recovery_window_in_days = 7
  tags                    = merge(var.tags, { Name = "${var.cluster_name}-app-config" })
}

resource "aws_secretsmanager_secret_version" "app_config" {
  secret_id = aws_secretsmanager_secret.app_config.id
  secret_string = jsonencode({
    OPEN_METEO_BASE_URL = "https://api.open-meteo.com/v1"
    PORT                = "3000"
  })
  lifecycle {
    ignore_changes = [secret_string]
  }
}
