# Fluent Bit DaemonSet Module

Installs `aws-for-fluent-bit` via Helm (chart version `0.1.34`) as a DaemonSet in `amazon-cloudwatch` namespace.

Ships pod logs to CloudWatch Logs via IRSA. Kinesis/Firehose/Elasticsearch outputs are disabled.

## Usage

```hcl
module "fluent_bit" {
  source = "../../modules/fluent-bit"

  aws_region     = "us-east-1"
  log_group_name = module.cloudwatch.eks_application_log_group
  irsa_role_arn  = module.iam.fluent_bit_role_arn
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `aws_region` | AWS region. | `string` | n/a |
| `log_group_name` | CloudWatch log group for application logs. | `string` | n/a |
| `irsa_role_arn` | IRSA role ARN for service account. | `string` | n/a |
| `chart_version` | Helm chart version. | `string` | `"0.1.34"` |
