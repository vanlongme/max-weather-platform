# External Secrets Operator Module

Installs the External Secrets Operator via Helm (chart version `0.10.4`) in `external-secrets` namespace, and creates a `ClusterSecretStore` resource backed by AWS Secrets Manager via IRSA.

## Usage

```hcl
module "external_secrets" {
  source = "../../modules/external-secrets"

  aws_region    = "us-east-1"
  irsa_role_arn = module.iam.external_secrets_role_arn
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `aws_region` | AWS region for Secrets Manager. | `string` | n/a |
| `irsa_role_arn` | IRSA role ARN. | `string` | n/a |
| `chart_version` | Helm chart version. | `string` | `"0.10.4"` |
