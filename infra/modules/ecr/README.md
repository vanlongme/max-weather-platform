# ECR Module

Creates ECR repositories for the application container images, with vulnerability scanning enabled and a lifecycle policy that:

1. Retains the last N (`keep_tagged_image_count`, default 10) images tagged with `staging-` or `prod-` prefix.
2. Expires untagged images after `untagged_image_expiry_days` (default 7) days.

By default creates two repositories:

- `max-weather-api` — the FastAPI service image
- `max-weather-lambda-authorizer` — the Lambda authorizer image

## Usage

```hcl
module "ecr" {
  source = "./modules/ecr"

  repositories = ["max-weather-api", "max-weather-lambda-authorizer"]
  tags         = local.common_tags
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `repositories` | List of ECR repository names to create. | `list(string)` | `["max-weather-api", "max-weather-lambda-authorizer"]` |
| `image_tag_mutability` | `MUTABLE` or `IMMUTABLE`. | `string` | `"MUTABLE"` |
| `scan_on_push` | Enable image vulnerability scanning on push. | `bool` | `true` |
| `keep_tagged_image_count` | Number of staging-/prod- tagged images to retain. | `number` | `10` |
| `untagged_image_expiry_days` | Days to keep untagged images before expiry. | `number` | `7` |
| `tags` | Common tags applied to all resources. | `map(string)` | `{}` |

## Outputs

| Name | Description |
|---|---|
| `repository_urls` | Map of name → repository URL (for `docker push`). |
| `repository_arns` | Map of name → repository ARN. |
| `repository_names` | List of created repository names. |
| `registry_ids` | Map of name → registry ID (AWS account ID). |
