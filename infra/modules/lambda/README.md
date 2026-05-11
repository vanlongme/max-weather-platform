# Lambda Module

Generic AWS Lambda deployment module. Packages source code from disk using Terraform's `archive_file` data source and deploys one or more functions via a `map(object)` variable.

## Design Decisions

- **IAM roles are external**: This module accepts `role_arn` per function; it does NOT create IAM roles. Use the `iam` module's `service_roles` to create roles and pass the ARN here.
- **No Function URL**: `function_url_config` is intentionally absent — all invocations go through API Gateway.
- **`archive_file` runs at plan time**: If `npm_install_dir` is set, a `null_resource` with `local-exec` runs `npm ci --omit=dev` in that directory before the zip is built. The trigger is `filemd5("${npm_install_dir}/package-lock.json")`, so any dependency change forces a re-zip and re-deploy.
- **Pre-create log groups**: Each function's CloudWatch log group is created with an explicit retention policy *before* the function, preventing Lambda from auto-creating one without retention.
- **Map-replace semantics**: Supplying `var.functions` replaces the default `{}` entirely (no merge). Re-declare all entries you want to keep.

## Prerequisites

Before running `terraform plan` or `terraform apply`, install production dependencies:

```bash
cd infra/envs/poc/lambdas/authorizer && npm ci --omit=dev
```

Or use the Makefile target:

```bash
make lambda-deps
```

Without this step, `archive_file` will fail at plan time because `node_modules/` is absent.

## Usage

```hcl
module "lambda" {
  source = "../../modules/lambda"

  name = local.master_prefix
  tags = local.common_tags

  functions = {
    authorizer = {
      source_dir      = "${path.root}/lambdas/authorizer"
      handler         = "src/index.handler"
      runtime         = "nodejs22.x"
      memory_size     = 128
      timeout         = 5
      role_arn        = module.iam.lambda_authorizer_role_arn
      npm_install_dir = "${path.root}/lambdas/authorizer"
      environment = {
        AUTHORIZER_SECRET_ARN = module.secrets.authorizer_jwt_secret_arn
        REQUIRED_SCOPE        = "weather-api/read"
        JWT_ISSUER            = "max-weather-authorizer"
      }
      invoke_principals = {
        api-gateway = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      }
    }
  }
}
```

## Resource Naming

With `var.name = "poc-max-weather"` and function key `authorizer`:

| Resource | Name |
|----------|------|
| Lambda function | `poc-max-weather-authorizer` |
| CloudWatch log group | `/aws/lambda/poc-max-weather-authorizer` |
| Lambda permission statement | `Allow-authorizer-api-gateway` |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | Resource name prefix (e.g. `poc-max-weather`). | `string` | n/a | yes |
| `tags` | Common tags merged onto every resource. | `map(string)` | `{}` | no |
| `functions` | Map of Lambda functions to deploy. Supplying this map REPLACES the default entirely. | `map(object)` | `{}` | no |

### `functions` object schema

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `source_dir` | `string` | required | Path to Lambda source directory (zipped by `archive_file`). |
| `handler` | `string` | required | Lambda handler (e.g. `src/index.handler`). |
| `runtime` | `string` | `"nodejs22.x"` | Lambda runtime identifier. |
| `memory_size` | `number` | `128` | Memory in MB. |
| `timeout` | `number` | `5` | Timeout in seconds. |
| `environment` | `map(string)` | `{}` | Environment variables injected into the function. |
| `log_retention_days` | `number` | `14` | CloudWatch log retention in days. |
| `function_name_suffix` | `string` | `""` | Optional suffix after key in resource name. |
| `role_arn` | `string` | required | Execution role ARN (from `iam` module). |
| `invoke_principals` | `map(string)` | `{}` | Map of label → source ARN for `aws_lambda_permission` resources. |
| `npm_install_dir` | `string` | `null` | If set, runs `npm ci --omit=dev` in this directory before archiving. |

## Outputs

| Name | Description |
|------|-------------|
| `function_arns` | Map of function key → ARN. |
| `function_names` | Map of function key → function name. |
| `function_invoke_arns` | Map of function key → invoke ARN (for API Gateway integrations). |
| `log_group_names` | Map of function key → CloudWatch log group name. |

## Requirements

| Name | Version |
|------|---------|
| terraform | `>= 1.9, < 2.0` |
| aws | `~> 6.0` |
| archive | `~> 2.4` |
| null | `~> 3.2` |
