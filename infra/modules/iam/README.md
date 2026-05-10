# IAM Module

Creates IAM roles and IRSA (IAM Roles for Service Accounts) trust policies for the cluster:

- **Jenkins EC2 instance profile + role** — ECR push/pull, EKS describe, Lambda deploy, CloudWatch Logs.
- **EKS node group role** — standard managed-node policies (worker, ECR read-only, CNI, SSM).
- **IRSA roles** — only created when `oidc_provider_arn` is non-empty (phase 2 apply):
  - Cluster Autoscaler (`kube-system:cluster-autoscaler`)
  - Fluent Bit (`amazon-cloudwatch:fluent-bit`)
  - AWS Load Balancer Controller (`kube-system:aws-load-balancer-controller`)
  - External Secrets Operator (`external-secrets:external-secrets`)

## Two-phase apply

The IRSA roles depend on the EKS OIDC provider, which is created by the EKS module. Use this module in two phases:

1. **Phase 1** — apply with `oidc_provider_arn = ""` (default). Only Jenkins and EKS node roles are created.
2. **Phase 2** — pass `oidc_provider_arn` and `oidc_provider_url` from the EKS module outputs. IRSA roles are created.

## Usage

```hcl
module "iam" {
  source = "./modules/iam"

  cluster_name      = "max-weather-staging"
  aws_region        = "us-east-1"
  aws_account_id    = data.aws_caller_identity.current.account_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  tags              = local.common_tags
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `cluster_name` | EKS cluster name, used for role naming. | `string` | — |
| `oidc_provider_arn` | ARN of the EKS OIDC provider for IRSA. Empty before EKS exists. | `string` | `""` |
| `oidc_provider_url` | URL of the EKS OIDC provider (without `https://`). | `string` | `""` |
| `aws_region` | AWS region used for ARN construction. | `string` | — |
| `aws_account_id` | AWS account ID for ARN construction. | `string` | — |
| `tags` | Common tags applied to all resources. | `map(string)` | `{}` |

## Outputs

| Name | Description |
|---|---|
| `jenkins_role_arn` / `jenkins_role_name` | Jenkins IAM role identifiers. |
| `jenkins_instance_profile_name` / `jenkins_instance_profile_arn` | Jenkins instance profile. |
| `eks_node_role_arn` / `eks_node_role_name` | EKS node group role. |
| `cluster_autoscaler_role_arn` | IRSA role ARN (empty if phase 1). |
| `fluent_bit_role_arn` | IRSA role ARN (empty if phase 1). |
| `aws_lb_controller_role_arn` | IRSA role ARN (empty if phase 1). |
| `external_secrets_role_arn` | IRSA role ARN (empty if phase 1). |
