# CloudWatch Log Groups Module

Creates CloudWatch log groups for the weather-api platform. The set of log
groups is fully driven by the `log_groups` variable; the module ships sensible
defaults that match the existing weather-api stack:

| Key | Log Group | Purpose |
|-----|-----------|---------|
| `eks_application` | `/aws/eks/{cluster}/application` | EKS pod logs (Fluent Bit). |
| `eks_control_plane` | `/aws/eks/{cluster}/cluster` | EKS control plane logs. |
| `lambda_authorizer` | `/aws/lambda/{cluster}-authorizer` | Lambda authorizer execution logs. |
| `api_gateway` | `/aws/apigateway/{cluster}-api` | API Gateway access logs. |
| `jenkins` | `/aws/ec2/{cluster}-jenkins` | Jenkins build/runtime logs. |

Each entry's `name` may include the literal placeholder `__CLUSTER_NAME__`,
which the module substitutes with `var.cluster_name` at apply time. An optional
`retention_days` per entry overrides the module-wide `var.log_retention_days`
default.

## Usage

Default set of 5 log groups:

```hcl
module "cloudwatch" {
  source             = "../../modules/cloudwatch"
  cluster_name       = "weather-api"
  log_retention_days = 30
  tags               = { Environment = "dev" }
}
```

### Adding a custom log group

Supplying `log_groups` **REPLACES** the defaults entirely — Terraform map
variables do not merge with defaults. To add a 6th group while keeping the
five built-ins, spread the defaults explicitly via a `local`:

```hcl
locals {
  default_log_groups = {
    eks_application = {
      name = "/aws/eks/__CLUSTER_NAME__/application"
    }
    eks_control_plane = {
      name = "/aws/eks/__CLUSTER_NAME__/cluster"
    }
    lambda_authorizer = {
      name = "/aws/lambda/__CLUSTER_NAME__-authorizer"
    }
    api_gateway = {
      name = "/aws/apigateway/__CLUSTER_NAME__-api"
    }
    jenkins = {
      name = "/aws/ec2/__CLUSTER_NAME__-jenkins"
    }
  }
}

module "cloudwatch" {
  source             = "../../modules/cloudwatch"
  cluster_name       = "weather-api"
  log_retention_days = 30
  tags               = { Environment = "dev" }

  log_groups = merge(
    local.default_log_groups,
    {
      my_app = {
        name           = "/aws/ec2/myapp"
        retention_days = 14
      }
    },
  )
}
```

If you only want a custom set (no defaults), pass `log_groups` directly without
the merge.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `cluster_name` | EKS cluster name prefix. | `string` | n/a |
| `log_retention_days` | Default log retention in days, applied when an entry's `retention_days` is null. | `number` | `30` |
| `tags` | Common tags. | `map(string)` | `{}` |
| `log_groups` | Map of CloudWatch log groups to create, keyed by short name. Each entry has `name` (may contain `__CLUSTER_NAME__`) and optional `retention_days`. **Supplying this variable REPLACES the defaults.** | <code>map(object({ name = string, retention_days = optional(number) }))</code> | The 5 entries listed above. |
| `cluster_name_placeholder` | Literal placeholder token in `log_groups[*].name` substituted with `var.cluster_name` at apply time. | `string` | `"__CLUSTER_NAME__"` |

## Outputs

| Name | Description |
|------|-------------|
| `log_group_names` | Map of key → log group name. |
| `log_group_arns` | Map of key → log group ARN. |
| `eks_application_log_group` | EKS app log group name. |
| `lambda_authorizer_log_group` | Lambda authorizer log group name. |
| `api_gateway_log_group` | API Gateway access log group name. |
