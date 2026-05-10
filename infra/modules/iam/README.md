# IAM Module

Creates IRSA (IAM Roles for Service Accounts) trust policies and inline policies for cluster workloads.

All IRSA roles are driven by a single `irsa_roles = map(object)` variable processed via `for_each`, so adding a new role from the env composition is a one-entry override. The module ships sane defaults for the five workloads this assessment uses:

- `jenkins` — `jenkins:jenkins` — ECR push/pull, EKS describe, Lambda deploy, CloudWatch Logs. Replaces the EC2 instance profile that was used by the deleted `infra/modules/jenkins` Terraform module.
- `cluster-autoscaler` — `kube-system:cluster-autoscaler`
- `fluent-bit` — `amazon-cloudwatch:fluent-bit`
- `aws-lb-controller` — `kube-system:aws-load-balancer-controller`
- `external-secrets` — `external-secrets:external-secrets`

Created role names are `${cluster_name}-${role_name_suffix}` (or `${cluster_name}-${map_key}` when `role_name_suffix` is omitted). Inline policies are named `${map_key}-policy`.

## Two-phase apply

The IRSA roles depend on the EKS OIDC provider, which is created by the EKS module. Use this module in two phases — the gating now applies **uniformly to all roles** (previously only `jenkins` was gated):

1. **Phase 1** — apply with `oidc_provider_arn = ""` (default). `for_each` evaluates to `{}` and zero IRSA roles are created.
2. **Phase 2** — pass `oidc_provider_arn` and `oidc_provider_url` from the EKS module outputs. All roles in `var.irsa_roles` are created.

## Placeholder substitution

Terraform variable defaults cannot reference other variables, so the `jenkins` policy's `LambdaDeployAccess` Resource ARN uses literal placeholder tokens:

| Placeholder         | Substituted with    |
|---------------------|---------------------|
| `__AWS_REGION__`    | `var.aws_region`    |
| `__AWS_ACCOUNT_ID__`| `var.aws_account_id`|
| `__CLUSTER_NAME__`  | `var.cluster_name`  |

`main.tf` performs nested `replace()` calls on `each.value.policy_json` at apply time. Custom roles you add via the `irsa_roles` map can use the same placeholders.

## Usage

Defaults — produces all five roles in phase 2:

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

Adding a custom (sixth) IRSA role from the env composition. The `irsa_roles` variable is the authoritative map: setting it replaces the defaults entirely. Re-declare the defaults you want kept and append your custom role:

```hcl
module "iam" {
  source = "./modules/iam"

  cluster_name      = "max-weather-staging"
  aws_region        = "us-east-1"
  aws_account_id    = data.aws_caller_identity.current.account_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  tags              = local.common_tags

  irsa_roles = {
    jenkins            = { namespace = "jenkins",          service_account = "jenkins",                      policy_json = jsonencode({ ... }) }
    cluster-autoscaler = { namespace = "kube-system",      service_account = "cluster-autoscaler",           policy_json = jsonencode({ ... }) }
    fluent-bit         = { namespace = "amazon-cloudwatch", service_account = "fluent-bit",                   policy_json = jsonencode({ ... }) }
    aws-lb-controller  = { namespace = "kube-system",      service_account = "aws-load-balancer-controller", policy_json = jsonencode({ ... }) }
    external-secrets   = { namespace = "external-secrets", service_account = "external-secrets",             policy_json = jsonencode({ ... }) }

    my-app = {
      namespace       = "default"
      service_account = "my-app"
      policy_json = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = "arn:aws:s3:::__CLUSTER_NAME__-bucket/*"
        }]
      })
    }
  }
}
```

## Inputs

| Name                | Description                                                                                                                                                       | Type                                                                                            | Default |
|---------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------|---------|
| `cluster_name`      | EKS cluster name, used for role naming.                                                                                                                           | `string`                                                                                        | —       |
| `oidc_provider_arn` | ARN of the EKS OIDC provider for IRSA. Empty before EKS exists (phase 1 — skips all IRSA roles).                                                                  | `string`                                                                                        | —       |
| `oidc_provider_url` | URL of the EKS OIDC provider (without `https://`).                                                                                                                | `string`                                                                                        | —       |
| `aws_region`        | AWS region used for ARN construction.                                                                                                                             | `string`                                                                                        | —       |
| `aws_account_id`    | AWS account ID for ARN construction.                                                                                                                              | `string`                                                                                        | —       |
| `tags`              | Common tags applied to all resources.                                                                                                                             | `map(string)`                                                                                   | `{}`    |
| `irsa_roles`        | Map of IRSA roles to create. Keyed by short name; each value defines `namespace`, `service_account`, `policy_json`, optional `role_name_suffix` (defaults to key).| `map(object({ namespace = string, service_account = string, policy_json = string, role_name_suffix = optional(string) }))` | 5 defaults (jenkins, cluster-autoscaler, fluent-bit, aws-lb-controller, external-secrets) |

## Outputs

| Name                          | Description                                                                  |
|-------------------------------|------------------------------------------------------------------------------|
| `irsa_role_arns`              | Map of IRSA role key to role ARN. Empty during phase 1.                      |
| `irsa_role_names`             | Map of IRSA role key to role name. Empty during phase 1.                     |
| `jenkins_role_arn`            | ARN of the Jenkins IRSA role (back-compat). Empty during phase 1.            |
| `jenkins_role_name`           | Name of the Jenkins IRSA role (back-compat). Empty during phase 1.           |
| `cluster_autoscaler_role_arn` | ARN of the Cluster Autoscaler IRSA role (back-compat). Empty during phase 1. |
| `fluent_bit_role_arn`         | ARN of the Fluent Bit IRSA role (back-compat). Empty during phase 1.         |
| `aws_lb_controller_role_arn`  | ARN of the AWS LB Controller IRSA role (back-compat). Empty during phase 1.  |
| `external_secrets_role_arn`   | ARN of the External Secrets IRSA role (back-compat). Empty during phase 1.   |
