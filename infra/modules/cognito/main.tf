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

resource "aws_cognito_user_pool_client" "app_clients" {
  for_each = var.app_clients

  name         = "${var.cluster_name}-${coalesce(each.value.name_suffix, each.key)}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret                      = each.value.generate_secret
  allowed_oauth_flows_user_pool_client = each.value.allowed_oauth_flows_user_pool_client
  allowed_oauth_flows                  = each.value.allowed_oauth_flows
  allowed_oauth_scopes                 = coalesce(each.value.allowed_oauth_scopes, ["${var.resource_server_identifier}/read"])

  supported_identity_providers = each.value.supported_identity_providers

  depends_on = [aws_cognito_resource_server.weather_api]
}
