# ECR Module

Creates ECR repositories for the application container images, with vulnerability scanning enabled and a lifecycle policy that:

1. Retains the last N (`keep_tagged_image_count`, default 10) most-recent tagged images matching `tag_prefix_list` (default `["staging-", "prod-"]`).
2. Expires untagged images after `untagged_image_expiry_days` (default 7) days.

By default creates two repositories:

- `max-weather-api` — the FastAPI service image
- `max-weather-lambda-authorizer` — the Lambda authorizer image

## Usage

Module-level defaults only:

```hcl
module "ecr" {
  source = "./modules/ecr"
  tags   = local.common_tags
}
```

Per-repository overrides (each value is an object whose fields fall back to module-level defaults when null):

```hcl
module "ecr" {
  source = "./modules/ecr"

  repositories = {
    "max-weather-api" = {}
    "max-weather-lambda-authorizer" = {
      keep_tagged_image_count    = 5
      untagged_image_expiry_days = 14
    }
    "max-weather-experimental" = {
      image_tag_mutability = "IMMUTABLE"
      tag_prefix_list      = ["v"]
    }
  }

  tags = local.common_tags
}
```

> Note: supplying `repositories` REPLACES the default map entirely. To keep the default repositories alongside additional ones, the caller must spread them in explicitly (e.g. include `"max-weather-api" = {}` and `"max-weather-lambda-authorizer" = {}` keys).

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `repositories` | Map of ECR repositories to create, keyed by repository name. Each value is an object with optional per-repo overrides; when an override is null the module-level default applies. | `map(object({ image_tag_mutability = optional(string), scan_on_push = optional(bool), keep_tagged_image_count = optional(number), untagged_image_expiry_days = optional(number), tag_prefix_list = optional(list(string), ["staging-", "prod-"]) }))` | `{ "max-weather-api" = {}, "max-weather-lambda-authorizer" = {} }` |
| `image_tag_mutability` | Module-level default for `MUTABLE` or `IMMUTABLE`. | `string` | `"MUTABLE"` |
| `scan_on_push` | Module-level default for image vulnerability scanning on push. | `bool` | `true` |
| `keep_tagged_image_count` | Module-level default for the number of tagged images to retain. | `number` | `10` |
| `untagged_image_expiry_days` | Module-level default for days to keep untagged images before expiry. | `number` | `7` |
| `tags` | Common tags applied to all resources. | `map(string)` | `{}` |

## Outputs

| Name | Description |
|---|---|
| `repository_urls` | Map of name → repository URL (for `docker push`). |
| `repository_arns` | Map of name → repository ARN. |
| `repository_names` | List of created repository names. |
| `registry_ids` | Map of name → registry ID (AWS account ID). |
