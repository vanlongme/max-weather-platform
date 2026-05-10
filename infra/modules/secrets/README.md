# Secrets Manager Module

Creates AWS Secrets Manager secrets for the weather-api platform. The set of
secrets is fully driven by the `secrets` variable; the module ships sensible
defaults that match the existing weather-api stack:

| Key | Default Secret Name | Purpose |
|-----|---------------------|---------|
| `cognito_client_secret` | `/{name}/cognito/client-secret` | Holds the Cognito app client secret. Populated externally after Cognito apply (Terraform manages the secret container; the secret value is `ignore_changes`). |
| `app_config` | `/{name}/app/config` | weather-api runtime configuration. Initial value is bootstrap-only; subsequent updates are managed externally. |

## Resource naming

When an entry's `name` field is omitted the module derives `${var.name}-${key}-secret`.
When `name` is supplied the module substitutes the literal placeholder
`__CLUSTER_NAME__` (configurable via `var.cluster_name_placeholder`) with
`var.name` at apply time, giving callers full control over the final secret
path. Both the resource `name` and the `Name` tag use the same derived value.

All managed secrets ship with `lifecycle { ignore_changes = [secret_string] }`
so callers can rotate values out-of-band without Terraform reverting them.

## Usage

Default set of two secrets (zero-config):

```hcl
module "secrets" {
  source = "../../modules/secrets"
  name   = "poc-max-weather"
  tags   = { Environment = "poc", Project = "max-weather" }
}
```

### Adding a custom secret

Supplying `secrets` **REPLACES** the defaults entirely — Terraform map variables
do not merge with defaults. To add a third secret while keeping the two
built-ins, re-declare them explicitly:

```hcl
module "secrets" {
  source = "../../modules/secrets"
  name   = "poc-max-weather"
  tags   = { Environment = "poc" }

  secrets = {
    cognito_client_secret = {
      name          = "/__CLUSTER_NAME__/cognito/client-secret"
      description   = "Cognito app client secret for weather-api OAuth2."
      initial_value = "PLACEHOLDER_REPLACE_AFTER_COGNITO_APPLY"
    }
    app_config = {
      name          = "/__CLUSTER_NAME__/app/config"
      description   = "weather-api application runtime configuration."
      initial_value = "{\"OPEN_METEO_BASE_URL\":\"https://api.open-meteo.com/v1\",\"PORT\":\"3000\"}"
    }
    third_party_api_key = {
      name        = "/__CLUSTER_NAME__/integrations/third-party-key"
      description = "Third-party integration API key (rotated externally)."
    }
  }
}
```

When `initial_value` is null, no `aws_secretsmanager_secret_version` is created
— the caller is responsible for populating the secret value externally. When
the entry's `name` is null, the module falls back to `${var.name}-${key}-secret`.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `name` | Name prefix applied to every resource (typically the master_prefix from the composition, e.g. `poc-max-weather`). | `string` | n/a |
| `tags` | Common tags. | `map(string)` | `{}` |
| `secrets` | Map of Secrets Manager secrets, keyed by short name. Each value has optional `name` (may contain `__CLUSTER_NAME__`; falls back to `${var.name}-${key}-secret` when null), optional `description`, optional `initial_value`, and optional `recovery_window_in_days` (default 7). **Supplying this variable REPLACES the defaults.** | <code>map(object({ name = optional(string), description = optional(string), initial_value = optional(string), recovery_window_in_days = optional(number, 7) }))</code> | `cognito_client_secret` + `app_config` |
| `cluster_name_placeholder` | Literal placeholder token in `secrets[*].name` substituted with `var.name` at apply time. | `string` | `"__CLUSTER_NAME__"` |

## Outputs

| Name | Description |
|------|-------------|
| `secret_arns` | Map of key → secret ARN. |
| `secret_names` | Map of key → secret name. |
| `cognito_client_secret_arn` | Back-compat alias for `secret_arns["cognito_client_secret"]`. |
| `cognito_client_secret_name` | Back-compat alias for `secret_names["cognito_client_secret"]`. |
| `app_config_secret_arn` | Back-compat alias for `secret_arns["app_config"]`. |
| `app_config_secret_name` | Back-compat alias for `secret_names["app_config"]`. |
