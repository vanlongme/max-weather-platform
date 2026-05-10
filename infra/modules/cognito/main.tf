resource "aws_cognito_user_pool" "main" {
  name = "${var.cluster_name}${var.user_pool_name_suffix}"

  password_policy {
    minimum_length    = var.password_policy.minimum_length
    require_lowercase = var.password_policy.require_lowercase
    require_uppercase = var.password_policy.require_uppercase
    require_numbers   = var.password_policy.require_numbers
    require_symbols   = var.password_policy.require_symbols
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
  name         = var.resource_server_name

  scope {
    scope_name        = var.resource_server_scope_name
    scope_description = var.resource_server_scope_description
  }
}

resource "aws_cognito_user_pool_client" "app_clients" {
  for_each = var.app_clients

  name         = "${var.cluster_name}-${coalesce(each.value.name_suffix, each.key)}${var.client_name_suffix}"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret                      = each.value.generate_secret
  allowed_oauth_flows_user_pool_client = each.value.allowed_oauth_flows_user_pool_client
  allowed_oauth_flows                  = each.value.allowed_oauth_flows
  allowed_oauth_scopes                 = coalesce(each.value.allowed_oauth_scopes, ["${var.resource_server_identifier}${var.default_oauth_scope_suffix}"])

  supported_identity_providers = each.value.supported_identity_providers

  depends_on = [aws_cognito_resource_server.weather_api]
}
