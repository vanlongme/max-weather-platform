# Secrets Manager Module

Creates AWS Secrets Manager secrets for the weather-api platform:

- **`/{cluster_name}/cognito/client-secret`** — Holds the Cognito app client secret. Populated externally after Cognito apply (Terraform manages the secret container; secret value is `ignore_changes`).
- **`/{cluster_name}/app/config`** — Application runtime config (non-sensitive defaults). Initial value is bootstrap-only; subsequent updates managed externally.

## Usage

```hcl
module "secrets" {
  source       = "../../modules/secrets"
  cluster_name = "weather-api"
  tags         = { Environment = "dev", Project = "weather-api" }
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `cluster_name` | EKS cluster name prefix. | `string` | n/a |
| `tags` | Common tags. | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `cognito_client_secret_arn` | ARN of the Cognito client secret. |
| `cognito_client_secret_name` | Name of the Cognito client secret. |
| `app_config_secret_arn` | ARN of the app config secret. |
| `app_config_secret_name` | Name of the app config secret. |
