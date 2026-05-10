# ECR Module

Creates ECR repositories for the application container images, with vulnerability scanning enabled and a lifecycle policy that:

1. Retains the last N (`keep_tagged_image_count`, default 10) most-recent tagged images matching `tag_prefix_list` (default `["staging-", "prod-"]`).
2. Expires untagged images after `untagged_image_expiry_days` (default 7) days.

Repository keys may include the literal placeholder `__CLUSTER_NAME__`, which the module substitutes with `var.cluster_name` at apply time (mirrors the pattern used by the cloudwatch and secrets modules). By default creates two repositories:

- `__CLUSTER_NAME__-api` — the application service image
- `__CLUSTER_NAME__-lambda-authorizer` — the Lambda authorizer image

## Usage

Module-level defaults only:

```hcl
module "ecr" {
  source       = "./modules/ecr"
  cluster_name = "max-weather"
  tags         = local.common_tags
}
```

Per-repository overrides (each value is an object whose fields fall back to module-level defaults when null):

```hcl
module "ecr" {
  source       = "./modules/ecr"
  cluster_name = "max-weather"

  repositories = {
    "__CLUSTER_NAME__-api" = {}
    "__CLUSTER_NAME__-lambda-authorizer" = {
      keep_tagged_image_count    = 5
      untagged_image_expiry_days = 14
    }
    "__CLUSTER_NAME__-experimental" = {
      image_tag_mutability = "IMMUTABLE"
      tag_prefix_list      = ["v"]
    }
  }

  tags = local.common_tags
}
```

> Note: supplying `repositories` REPLACES the default map entirely. To keep the default repositories alongside additional ones, the caller must spread them in explicitly (e.g. include `"__CLUSTER_NAME__-api" = {}` and `"__CLUSTER_NAME__-lambda-authorizer" = {}` keys).

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `cluster_name` | Cluster name prefix used to interpolate the literal placeholder `__CLUSTER_NAME__` in repository keys. | `string` | n/a |
| `repositories` | Map of ECR repositories to create, keyed by repository name (may contain `__CLUSTER_NAME__`). Each value is an object with optional per-repo overrides; when an override is null the module-level default applies. | `map(object({ image_tag_mutability = optional(string), scan_on_push = optional(bool), keep_tagged_image_count = optional(number), untagged_image_expiry_days = optional(number), tag_prefix_list = optional(list(string), ["staging-", "prod-"]) }))` | `{ "__CLUSTER_NAME__-api" = {}, "__CLUSTER_NAME__-lambda-authorizer" = {} }` |
| `image_tag_mutability` | Module-level default for `MUTABLE` or `IMMUTABLE`. | `string` | `"MUTABLE"` |
| `scan_on_push` | Module-level default for image vulnerability scanning on push. | `bool` | `true` |
| `keep_tagged_image_count` | Module-level default for the number of tagged images to retain. | `number` | `10` |
| `untagged_image_expiry_days` | Module-level default for days to keep untagged images before expiry. | `number` | `7` |
| `tags` | Common tags applied to all resources. | `map(string)` | `{}` |
| `cluster_name_placeholder` | Literal placeholder in repository keys substituted with `var.cluster_name` at apply time. | `string` | `"__CLUSTER_NAME__"` |
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
