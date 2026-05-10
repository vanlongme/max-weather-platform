# ECR Module

Creates ECR repositories for the application container images, with vulnerability scanning enabled and a lifecycle policy that:

1. Retains the last N (`keep_tagged_image_count`, default 10) most-recent tagged images matching `tag_prefix_list` (default `["staging-", "prod-"]`).
2. Expires untagged images after `untagged_image_expiry_days` (default 7) days.

## Resource naming

Each repository's final name is derived as `${var.name}-${key}-repo`, where `key` is the short identifier supplied in the `repositories` map. The same value is used for the `Name` tag.

By default the module ships two repositories:

| Key | Final repository name (with `var.name = "poc-max-weather"`) |
|-----|-------------------------------------------------------------|
| `api`         | `poc-max-weather-api-repo`         |
| `base-nodejs` | `poc-max-weather-base-nodejs-repo` |

> Note: The `lambda-authorizer` ECR repository was removed from defaults — the Lambda authorizer is deployed as a ZIP package via the `lambda` module and does not use a container image.

## Usage

Module-level defaults only:

```hcl
module "ecr" {
  source = "./modules/ecr"
  name   = "poc-max-weather"
  tags   = local.common_tags
}
```

Per-repository overrides (each value is an object whose fields fall back to module-level defaults when null):

```hcl
module "ecr" {
  source = "./modules/ecr"
  name   = "poc-max-weather"

  repositories = {
    api = {}
    lambda-authorizer = {
      keep_tagged_image_count    = 5
      untagged_image_expiry_days = 14
    }
    experimental = {
      image_tag_mutability = "IMMUTABLE"
      tag_prefix_list      = ["v"]
    }
  }

  tags = local.common_tags
}
```

> Note: supplying `repositories` REPLACES the default map entirely. To keep the default repositories alongside additional ones, the caller must re-declare them explicitly (e.g. include `api = {}`, `lambda-authorizer = {}`, and `base-nodejs = {}` keys).

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `name` | Name prefix applied to every resource (typically the master_prefix from the composition, e.g. `poc-max-weather`). Each repository's final name is `${var.name}-${key}-repo`. | `string` | n/a |
| `repositories` | Map of ECR repositories to create, keyed by short name. Each value is an object with optional per-repo overrides; when an override is null the module-level default applies. | `map(object({ image_tag_mutability = optional(string), scan_on_push = optional(bool), keep_tagged_image_count = optional(number), untagged_image_expiry_days = optional(number), tag_prefix_list = optional(list(string), ["staging-", "prod-"]) }))` | `{ api = {}, lambda-authorizer = {}, base-nodejs = {} }` |
| `image_tag_mutability` | Module-level default for `MUTABLE` or `IMMUTABLE`. | `string` | `"MUTABLE"` |
| `scan_on_push` | Module-level default for image vulnerability scanning on push. | `bool` | `true` |
| `keep_tagged_image_count` | Module-level default for the number of tagged images to retain. | `number` | `10` |
| `untagged_image_expiry_days` | Module-level default for days to keep untagged images before expiry. | `number` | `7` |
| `tags` | Common tags applied to all resources. | `map(string)` | `{}` |
| `lifecycle_keep_tagged_priority` | `rulePriority` of the keep-tagged lifecycle rule. | `number` | `1` |
| `lifecycle_expire_untagged_priority` | `rulePriority` of the expire-untagged lifecycle rule. | `number` | `2` |
| `lifecycle_keep_tagged_description_template` | Description template for the keep-tagged rule (`__COUNT__` → per-repo `keep_tagged_image_count`). | `string` | `"Keep last __COUNT__ tagged images"` |
| `lifecycle_expire_untagged_description_template` | Description template for the expire-untagged rule (`__COUNT__` → per-repo `untagged_image_expiry_days`). | `string` | `"Expire untagged images after __COUNT__ days"` |
| `lifecycle_count_placeholder` | Literal placeholder substituted in lifecycle rule descriptions. | `string` | `"__COUNT__"` |
| `lifecycle_tag_status_tagged` | `tagStatus` for the keep-tagged rule. | `string` | `"tagged"` |
| `lifecycle_tag_status_untagged` | `tagStatus` for the expire-untagged rule. | `string` | `"untagged"` |
| `lifecycle_count_type_more_than` | `countType` for "retain at most N images". | `string` | `"imageCountMoreThan"` |
| `lifecycle_count_type_since_pushed` | `countType` for "expire images older than N units". | `string` | `"sinceImagePushed"` |
| `lifecycle_count_unit` | `countUnit` for the expire-untagged rule. | `string` | `"days"` |
| `lifecycle_action_type` | Action type for ECR lifecycle rules. | `string` | `"expire"` |

## Outputs

| Name | Description |
|---|---|
| `repository_urls` | Map of name → repository URL (for `docker push`). |
| `repository_arns` | Map of name → repository ARN. |
| `repository_names` | List of created repository names. |
| `registry_ids` | Map of name → registry ID (AWS account ID). |
