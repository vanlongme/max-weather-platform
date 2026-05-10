# Cognito Module

Creates a Cognito User Pool, Resource Server, hosted UI domain, and one or more App Clients (default: a single `client_credentials` OAuth2 M2M client for the weather-api).

## Usage

Defaults — single `weather-api` client (zero-config):

```hcl
module "cognito" {
  source        = "../../modules/cognito"
  cluster_name  = "weather-api"
  domain_prefix = "weather-api-dev-12345"
  tags          = { Environment = "dev" }
}
```

Multiple clients — supplying `app_clients` REPLACES the default map entirely, so include `weather_api` if you still want it:

```hcl
module "cognito" {
  source        = "../../modules/cognito"
  cluster_name  = "weather-api"
  domain_prefix = "weather-api-dev-12345"

  app_clients = {
    weather_api = { name_suffix = "weather-api" }
    analytics   = { name_suffix = "analytics", allowed_oauth_scopes = ["weather-api/read"] }
  }
}
```

The token endpoint and JWKS URI are exposed as outputs for the API Gateway / Lambda authorizer to validate JWTs.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `cluster_name` | Project prefix for resource naming. | `string` | n/a |
| `domain_prefix` | Globally-unique prefix for Cognito hosted UI domain. | `string` | n/a |
| `resource_server_identifier` | URI identifier for the resource server. | `string` | `"weather-api"` |
| `tags` | Common tags. | `map(string)` | `{}` |
| `app_clients` | Map of app clients to create, keyed by short name. Each value is an object with optional `name_suffix` (defaults to the map key), `generate_secret` (default `true`), `allowed_oauth_flows_user_pool_client` (default `true`), `allowed_oauth_flows` (default `["client_credentials"]`), `allowed_oauth_scopes` (default `["${resource_server_identifier}/read"]`), `supported_identity_providers` (default `["COGNITO"]`). Final client name is `"${cluster_name}-${name_suffix}-client"`. **Supplying this variable replaces the default map entirely.** | `map(object({...}))` | `{ weather_api = { name_suffix = "weather-api" } }` |

## Outputs

| Name | Description |
|------|-------------|
| `user_pool_id` | Cognito User Pool ID. |
| `user_pool_arn` | Cognito User Pool ARN. |
| `domain` | Cognito hosted UI domain prefix. |
| `token_endpoint` | OAuth2 token endpoint URL. |
| `jwks_uri` | JWKS URI for JWT validation. |
| `client_ids` | Map of app client key to client ID. |
| `client_secrets` | Map of app client key to client secret (sensitive). |
| `client_id` | Back-compat alias for `client_ids["weather_api"]`. |
| `client_secret` | Back-compat alias for `client_secrets["weather_api"]` (sensitive). |
| `resource_server_scope` | Full scope string (`weather-api/read`). |
