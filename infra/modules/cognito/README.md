# Cognito Module

Creates a Cognito User Pool, Resource Server, App Client (`client_credentials` OAuth2 M2M flow), and hosted UI domain for the weather-api platform.

## Usage

```hcl
module "cognito" {
  source        = "../../modules/cognito"
  cluster_name  = "weather-api"
  domain_prefix = "weather-api-dev-12345"
  tags          = { Environment = "dev" }
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

## Outputs

| Name | Description |
|------|-------------|
| `user_pool_id` | Cognito User Pool ID. |
| `user_pool_arn` | Cognito User Pool ARN. |
| `domain` | Cognito hosted UI domain prefix. |
| `token_endpoint` | OAuth2 token endpoint URL. |
| `jwks_uri` | JWKS URI for JWT validation. |
| `client_id` | App client ID. |
| `client_secret` | App client secret (sensitive). |
| `resource_server_scope` | Full scope string (`weather-api/read`). |
