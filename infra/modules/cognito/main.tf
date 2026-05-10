data "aws_region" "current" {}

resource "aws_cognito_user_pool" "main" {
  name = "${var.cluster_name}-user-pool"

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  tags = var.tags
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = var.domain_prefix
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_resource_server" "weather_api" {
  user_pool_id = aws_cognito_user_pool.main.id
  identifier   = var.resource_server_identifier
  name         = "Weather API"

  scope {
    scope_name        = "read"
    scope_description = "Read access to weather API."
  }
}

resource "aws_cognito_user_pool_client" "weather_api" {
  name         = "${var.cluster_name}-weather-api-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_scopes                 = ["${var.resource_server_identifier}/read"]

  supported_identity_providers = ["COGNITO"]

  depends_on = [aws_cognito_resource_server.weather_api]
}
