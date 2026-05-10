# IAM Module

Multi-type IAM role factory. Creates roles + inline policies + managed-policy
attachments for three trust models — pick whichever you need; unused types
stay empty:

| Type | Trust principal | Use case | Default |
|------|-----------------|----------|---------|
| `service_roles` | AWS service principal (e.g. `lambda.amazonaws.com`, `ec2.amazonaws.com`) | Lambda execution roles, EC2 instance roles, ECS task roles | `{}` |
| `irsa_roles` | OIDC web-identity (EKS) | Legacy IRSA workloads | `{}` (skipped unless `oidc_provider_arn` + `oidc_provider_url` are passed) |
| `pod_identity_roles` | `pods.eks.amazonaws.com` (EKS Pod Identity) | All EKS workloads on 1.30+ | 5 built-in workload roles (jenkins, cluster-autoscaler, fluent-bit, aws-lb-controller, external-secrets) |

**Pod Identity associations are created by the `eks` module**, not here. This
module emits an `aws_iam_role` per pod_identity_roles entry plus the
`pod_identity_role_bindings` output (`{namespace, service_account, role_arn}`),
which is fed straight into the eks module's `pod_identity_associations` input.

## Usage

```hcl
module "iam" {
  source = "../../modules/iam"

  cluster_name   = var.cluster_name
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id
  tags           = local.common_tags

  # Pod Identity roles default to the five built-in workload roles — override
  # to add custom roles (replaces the default map entirely).
  pod_identity_roles = var.pod_identity_roles

  # Optional: traditional service roles (Lambda, EC2, etc.)
  service_roles = {
    weather_lambda = {
      service_principals  = ["lambda.amazonaws.com"]
      managed_policy_arns = ["arn:__AWS_PARTITION__:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
      policy_json = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = "arn:__AWS_PARTITION__:secretsmanager:__AWS_REGION__:__AWS_ACCOUNT_ID__:secret:/__CLUSTER_NAME__/*"
        }]
      })
    }
  }

  # Optional: IRSA roles (legacy — prefer pod_identity_roles)
  irsa_roles        = {}
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
}

module "eks" {
  source = "../../modules/eks"
  # ...
  pod_identity_associations = module.iam.pod_identity_role_bindings
  jenkins_role_arn          = module.iam.jenkins_role_arn
}
```

## Inline policy templating

`policy_json` strings (in any role type) accept four literal placeholders that
are substituted at apply time:

| Placeholder | Substituted with |
|-------------|------------------|
| `__AWS_PARTITION__` | `data.aws_partition.current.partition` |
| `__AWS_REGION__` | `var.aws_region` |
| `__AWS_ACCOUNT_ID__` | `var.aws_account_id` |
| `__CLUSTER_NAME__` | `var.cluster_name` |

This is what lets the Jenkins default policy scope `lambda:UpdateFunctionCode`
to `arn:__AWS_PARTITION__:lambda:__AWS_REGION__:__AWS_ACCOUNT_ID__:function:__CLUSTER_NAME__-*`
without baking partition/region/account into the policy JSON.

## Role naming

Each role is named `${var.cluster_name}-${role_name_suffix or map_key}`. Set
`role_name_suffix` per entry to decouple the IAM role name from the map key.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `cluster_name` | EKS cluster name (used for role naming + policy templating). | `string` | n/a | yes |
| `aws_region` | AWS region (substitutes `__AWS_REGION__`). | `string` | n/a | yes |
| `aws_account_id` | AWS account ID (substitutes `__AWS_ACCOUNT_ID__`). | `string` | n/a | yes |
| `tags` | Common tags. | `map(string)` | `{}` | no |
| `service_roles` | AWS service-principal roles (Lambda, EC2, etc.). | `map(object)` | `{}` | no |
| `irsa_roles` | OIDC web-identity roles (legacy IRSA). Requires `oidc_provider_arn` + `oidc_provider_url`. | `map(object)` | `{}` | no |
| `pod_identity_roles` | Pod Identity roles. `null` ships the 5 built-in defaults; supplying a map replaces them. | `map(object)` | `null` | no |
| `oidc_provider_arn` | EKS OIDC provider ARN (only for IRSA). | `string` | `""` | no |
| `oidc_provider_url` | EKS OIDC provider URL without `https://` (only for IRSA). | `string` | `""` | no |
| `inline_policy_name_suffix` | Suffix for inline policy names. | `string` | `"-policy"` | no |
| `partition_placeholder` / `region_placeholder` / `account_id_placeholder` / `cluster_name_placeholder` | Literal placeholder tokens substituted in policy JSON. | `string` | `__AWS_PARTITION__` / `__AWS_REGION__` / `__AWS_ACCOUNT_ID__` / `__CLUSTER_NAME__` | no |
| Pod Identity / IRSA / service assume-role literals | See `variables.tf`. Every literal in the assume-role policies is overridable but defaults match AWS documented values. | various | various | no |

## Outputs

| Name | Description |
|------|-------------|
| `service_role_arns` / `service_role_names` | Maps keyed by `service_roles` map key. |
| `irsa_role_arns` / `irsa_role_names` | Maps keyed by `irsa_roles` map key. |
| `pod_identity_role_arns` / `pod_identity_role_names` | Maps keyed by `pod_identity_roles` map key. |
| `pod_identity_role_bindings` | Map of `{namespace, service_account, role_arn}` per Pod Identity role — pass directly to `module.eks.pod_identity_associations`. |
| `jenkins_role_arn` / `jenkins_role_name` | Convenience accessors for the built-in Jenkins Pod Identity role. |
| `cluster_autoscaler_role_arn` / `fluent_bit_role_arn` / `aws_lb_controller_role_arn` / `external_secrets_role_arn` | Convenience accessors for the other four built-in Pod Identity roles. |

## Requirements

| Name | Version |
|------|---------|
| terraform | `>= 1.9, < 2.0` |
| aws | `~> 6.0` |
