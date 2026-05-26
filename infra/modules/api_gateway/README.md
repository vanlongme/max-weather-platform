# API Gateway Module

Provisions an AWS API Gateway v2 (HTTP API) fronting EKS-hosted services
through a Network Load Balancer, with a Lambda REQUEST-type authorizer for
HS256 JWT verification. Supports **multi-stage** deployments from a single
API: each entry in `var.stages` produces a dedicated stage plus per-stage
weather and healthz integrations/routes.

## Design Decisions

- **HTTP API v2 only**: Uses `aws_apigatewayv2_*` resources. The deprecated
  v1 `aws_api_gateway_*` REST API resources are not supported.
- **`authorizer_result_ttl_in_seconds = 0`** (CRITICAL): API Gateway caches
  authorizer responses keyed only on the `Authorization` header, **not** the
  stage. A cached staging token would otherwise authorize a prod request.
  Setting TTL to 0 forces a per-request Lambda invoke. Do not change this.
- **No CORS, WAF, custom domain, ACM, throttling, or usage plans**: This is
  a POC composition. Add these as needed at a higher layer.
- **No `aws_apigatewayv2_deployment`**: Each stage uses `auto_deploy = true`
  which manages deployments implicitly.
- **No provider block**: Per `infra/modules/AGENTS.md`, modules inherit the
  caller's provider configuration.
- **`locals` discipline**: All `locals` blocks live in `locals.tf` per the
  repository-wide rule in `AGENTS.md`. Never inline `locals { ... }` in
  `main.tf`, `outputs.tf`, etc.

## Stage URL Pattern

Each stage is reachable at:

```
https://<api_id>.execute-api.<region>.amazonaws.com/<stage_name>
```

The module emits this as `outputs.invoke_urls[<stage_name>]`.

## First-Apply Gotcha: the `$default` Stage

When AWS creates an HTTP API, it automatically provisions a `$default` stage
that this module does not manage. After the first apply, delete it manually
so that only the Terraform-managed stages exist:

```bash
aws apigatewayv2 delete-stage \
  --api-id "$(terraform output -raw api_gateway_api_id)" \
  --stage-name '$default' \
  --region us-east-1
```

If `$default` is left in place, traffic to the bare API hostname (no path
prefix) reaches it unauthenticated. The Terraform-managed stages (`staging`,
`prod`, etc.) remain isolated under their stage-name path prefix.

## Usage

```hcl
module "api_gateway" {
  source = "../../modules/api_gateway"

  name                  = local.master_prefix
  lambda_authorizer_arn = module.lambda.function_arns["authorizer"]
  lambda_function_name  = module.lambda.function_names["authorizer"]
  nlb_dns               = data.aws_lb.ingress_nlb.dns_name

  stages = {
    staging = {
      ingress_host = "staging.max-weather.local"
      secret_arn   = module.secrets.authorizer_jwt_secret_arn_staging
      issuer       = "max-weather-authorizer-staging"
      scope        = "weather-api/read"
    }
    prod = {
      ingress_host = "prod.max-weather.local"
      secret_arn   = module.secrets.authorizer_jwt_secret_arn_prod
      issuer       = "max-weather-authorizer-prod"
      scope        = "weather-api/read"
    }
  }

  tags = local.common_tags
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | Resource name prefix (typically `master_prefix`, e.g. `poc-max-weather`). | `string` | n/a | yes |
| `lambda_authorizer_arn` | ARN of the Lambda function used as the JWT authorizer. | `string` | n/a | yes |
| `lambda_function_name` | Name of the Lambda function (used for `aws_lambda_permission`). | `string` | n/a | yes |
| `nlb_dns` | DNS name of the Network Load Balancer fronting the EKS ingress. Used as the integration URI host in INTERNET mode (default). Still required when VPC Link mode is enabled (kept for backward-compatible signature, ignored at integration time). | `string` | n/a | yes |
| `ingress_host` | Static Host header value injected via `overwrite:header.Host` so ingress-nginx host-based routing matches. | `string` | n/a | yes |
| `stages` | Map of API Gateway stages to create. Each stage gets its own integrations and routes. See schema below. | `map(object)` | n/a | yes |
| `tags` | Common tags to apply to all resources. | `map(string)` | `{}` | no |
| `vpc_link_subnet_ids` | Private subnet IDs (one per AZ) for the API Gateway VPC Link ENIs. Empty list (default) disables VPC Link and keeps `connection_type=INTERNET`. Supplying a non-empty list enables VPC Link mode. | `list(string)` | `[]` | no |
| `vpc_link_security_group_ids` | Security group IDs attached to the VPC Link ENIs. Only used when `vpc_link_subnet_ids` is non-empty. | `list(string)` | `[]` | no |
| `nlb_listener_arn` | ARN of the NLB listener (e.g. port 80) that integrations target when VPC Link mode is enabled. Only used when `vpc_link_subnet_ids` is non-empty. | `string` | `""` | no |

### `stages` object schema

| Field | Type | Description |
|-------|------|-------------|
| `ingress_host` | `string` | Host header to inject via `overwrite:header.Host` so ingress-nginx host-based routing matches (e.g. `staging.max-weather.local`). |
| `secret_arn` | `string` | ARN of the per-stage Secrets Manager secret holding the HS256 signing key. Consumed by the Lambda authorizer via the per-stage context the authorizer reads from environment / lookup. |
| `issuer` | `string` | Expected JWT `iss` claim value for this stage. Per-stage isolation. |
| `scope` | `string` | Required JWT scope for this stage. |

## VPC Link mode (private cluster)

By default this module uses `connection_type = "INTERNET"` and routes API
Gateway → NLB traffic via the public DNS name of the NLB. When the NLB is
internal (no public IPs), API Gateway must reach it over a private network
hop instead.

Supply `vpc_link_subnet_ids` (and the companion inputs) to enable **VPC Link
mode**. The module then creates an `aws_apigatewayv2_vpc_link` whose ENIs
land in the supplied private subnets, and both `weather` / `healthz`
integrations switch to `connection_type = "VPC_LINK"`, with
`integration_uri = var.nlb_listener_arn`.

```hcl
module "api_gateway" {
  source = "../../modules/api_gateway"

  name                  = local.master_prefix
  lambda_authorizer_arn = module.lambda.function_arns["authorizer"]
  lambda_function_name  = module.lambda.function_names["authorizer"]
  nlb_dns               = data.aws_lb.ingress_nlb.dns_name
  ingress_host          = "staging.max-weather.local"

  # Enable VPC Link mode — API GW → NLB traffic stays on the AWS backbone.
  vpc_link_subnet_ids         = module.networking.private_subnet_ids
  vpc_link_security_group_ids = [aws_security_group.apigw_vpclink.id]
  nlb_listener_arn            = data.aws_lb_listener.ingress_nlb_80.arn

  stages = { /* ... */ }
  tags   = local.common_tags
}
```

Notes:

- `nlb_dns` remains required (backward-compatible signature). In VPC Link
  mode it is unused at integration time but kept so callers/INTERNET-mode
  consumers do not break.
- The VPC Link `Status` becomes `AVAILABLE` after ~30 s. Verify with
  `aws apigatewayv2 get-vpc-links --query 'Items[0]'`.
- The VPC Link SG only needs egress to the NLB targets (typically VPC CIDR
  on the listener ports). It does NOT need ingress rules.

## Outputs

| Name | Description |
|------|-------------|
| `api_id` | ID of the HTTP API. |
| `invoke_urls` | Map of stage name → fully-qualified stage invoke URL (`https://<api_id>.execute-api.<region>.amazonaws.com/<stage>`). |
| `authorizer_id` | ID of the Lambda authorizer. |

## Requirements

| Name | Version |
|------|---------|
| terraform | `>= 1.9, < 2.0` |
| aws | `~> 6.0` |

## Cross-References

- Repository-wide conventions: [`AGENTS.md`](../../../AGENTS.md), [`infra/modules/AGENTS.md`](../AGENTS.md) — especially the **locals-only-in-locals.tf** rule.
