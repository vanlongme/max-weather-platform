# CloudWatch Log Groups Module

Creates CloudWatch log groups for the weather-api platform:

| Key | Log Group | Purpose |
|-----|-----------|---------|
| `eks_application` | `/aws/eks/{cluster}/application` | EKS pod logs (Fluent Bit). |
| `eks_control_plane` | `/aws/eks/{cluster}/cluster` | EKS control plane logs. |
| `lambda_authorizer` | `/aws/lambda/{cluster}-authorizer` | Lambda authorizer execution logs. |
| `api_gateway` | `/aws/apigateway/{cluster}-api` | API Gateway access logs. |
| `jenkins` | `/aws/ec2/{cluster}-jenkins` | Jenkins build/runtime logs. |

## Usage

```hcl
module "cloudwatch" {
  source             = "../../modules/cloudwatch"
  cluster_name       = "weather-api"
  log_retention_days = 30
  tags               = { Environment = "dev" }
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `cluster_name` | EKS cluster name prefix. | `string` | n/a |
| `log_retention_days` | Log retention in days. | `number` | `30` |
| `tags` | Common tags. | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `log_group_names` | Map of key → log group name. |
| `log_group_arns` | Map of key → log group ARN. |
| `eks_application_log_group` | EKS app log group name. |
| `lambda_authorizer_log_group` | Lambda authorizer log group name. |
| `api_gateway_log_group` | API Gateway access log group name. |
