# EKS Module

Thin wrapper around the upstream
[`terraform-aws-modules/eks/aws`](https://github.com/terraform-aws-modules/terraform-aws-eks)
(v20.24) that provisions:

- An EKS cluster with public + private API endpoints, public access locked to
  `var.allowed_cidrs` (`0.0.0.0/0` is rejected by validation).
- One or more managed node groups driven by the `eks_managed_node_groups` map
  (default: a single `general` group — AL2023, ON_DEMAND `t3.medium`, min 2 /
  max 10 / desired 2 — tagged for Cluster Autoscaler discovery).
- The bundled `cluster_addons`: CoreDNS, kube-proxy, VPC CNI, EKS Pod Identity
  Agent (the last two installed `before_compute`). Override via `cluster_addons`.
- IRSA enabled and an OIDC provider exported as outputs.
- Two built-in access entries: `operator` (cluster-admin) and `jenkins`
  (namespace-scoped Edit on `weather-staging` and `weather-prod`). Additional
  entries can be merged in via `access_entries`.
- Karpenter scaffolding via the upstream
  [`karpenter` sub-module](https://github.com/terraform-aws-modules/terraform-aws-eks/tree/master/modules/karpenter):
  controller IRSA role, node IAM role + instance profile, SQS queue, and
  EventBridge rules. The actual Karpenter Helm chart and `EC2NodeClass` /
  `NodePool` objects live under `k8s/helm/karpenter/`.

## Usage

```hcl
module "eks" {
  source = "../../modules/eks"

  cluster_name    = "max-weather"
  cluster_version = "1.30"

  vpc_id     = module.networking.vpc_id
  subnet_ids = module.networking.public_subnet_ids # POC: public; prod: private

  allowed_cidrs          = ["203.0.113.10/32"]
  operator_principal_arn = data.aws_caller_identity.current.arn
  jenkins_role_arn       = module.iam.jenkins_role_arn

  eks_managed_node_groups = {
    general = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 10
      desired_size   = 2
      labels         = { role = "general" }
    }
  }

  tags = {
    Project     = "max-weather"
    Environment = "poc"
    ManagedBy   = "terraform"
  }
}
```

### Multiple node groups

Pass several entries in the same map to provision multiple node groups in one
shot. Per-group `tags` are merged with `var.tags` and the autoscaler discovery
tags automatically.

```hcl
eks_managed_node_groups = {
  general = {
    instance_types = ["t3.medium"]
    min_size       = 2
    max_size       = 10
    desired_size   = 2
    labels         = { role = "general" }
  }

  spot = {
    instance_types = ["t3.large", "t3a.large"]
    capacity_type  = "SPOT"
    min_size       = 0
    max_size       = 20
    desired_size   = 0
    labels         = { role = "spot" }
    taints = {
      spot = { key = "spot", value = "true", effect = "NO_SCHEDULE" }
    }
  }
}
```

A complete invocation lives in [`terraform.tfvars.example`](./terraform.tfvars.example).

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `cluster_name` | EKS cluster name. | `string` | n/a | yes |
| `cluster_version` | Kubernetes version. | `string` | `"1.30"` | no |
| `vpc_id` | VPC ID for the cluster. | `string` | n/a | yes |
| `subnet_ids` | Subnet IDs for nodes + control plane ENIs (POC: public, prod: private). | `list(string)` | n/a | yes |
| `allowed_cidrs` | CIDRs allowed to reach the public EKS API endpoint. `0.0.0.0/0` is rejected. | `list(string)` | n/a | yes |
| `operator_principal_arn` | IAM principal granted cluster-admin via access entry. | `string` | n/a | yes |
| `jenkins_role_arn` | Jenkins IRSA role granted Edit on `weather-staging`/`weather-prod`. Empty -> jenkins access entry omitted (phase 1). | `string` | `""` | no |
| `eks_managed_node_groups` | Map of EKS managed node group definitions, keyed by group name. Passed through to the upstream `eks_managed_node_groups` input. | `map(object)` | single `general` group | no |
| `eks_managed_node_group_defaults` | Defaults applied to every managed node group; per-group overrides win. | `any` | `{ attach_cluster_primary_security_group = false }` | no |
| `cluster_addons` | Map of EKS add-ons to enable. Passed through to the upstream `cluster_addons` input. | `any` | CoreDNS / kube-proxy / VPC CNI / Pod Identity Agent | no |
| `access_entries` | Extra access entries merged after the built-in operator + jenkins entries (user-supplied entries win on key collision). | `any` | `{}` | no |
| `tags` | Common tags applied to all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_name` | EKS cluster name. |
| `cluster_endpoint` | API server endpoint URL. |
| `cluster_ca_data` | Base64-encoded cluster CA. |
| `cluster_version` | Kubernetes version. |
| `cluster_oidc_issuer_url` | OIDC issuer URL. |
| `oidc_provider_arn` | IAM OIDC provider ARN (for IRSA trust policies). |
| `oidc_provider_url` | OIDC provider URL without `https://` prefix. |
| `cluster_security_group_id` | EKS-managed control plane SG ID. |
| `node_security_group_id` | SG ID attached to managed node group instances. |
| `karpenter_queue_name` | SQS queue name consumed by the Karpenter controller. |
| `karpenter_iam_role_arn` | Karpenter controller IRSA role ARN. |
| `karpenter_node_iam_role_arn` | IAM role ARN attached to Karpenter-provisioned nodes. |
| `karpenter_node_iam_role_name` | IAM role name attached to Karpenter-provisioned nodes (referenced from `EC2NodeClass.role`). |
| `karpenter_instance_profile_name` | Instance profile name attached to Karpenter-provisioned nodes. |

## Requirements

| Name | Version |
|------|---------|
| terraform | `>= 1.9, < 2.0` |
| aws | `~> 5.60` |
| upstream `terraform-aws-modules/eks/aws` | `~> 20.24` |
