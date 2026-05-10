# EKS Module

Thin wrapper around the upstream
[`terraform-aws-modules/eks/aws`](https://github.com/terraform-aws-modules/terraform-aws-eks)
(v20.24) that provisions:

- An EKS cluster with public + private API endpoints, public access locked to
  `var.allowed_cidrs` (`0.0.0.0/0` is rejected by validation).
- A single managed node group `general` (AL2023, ON_DEMAND `t3.medium` by
  default, min 2 / max 10 / desired 2) tagged for Cluster Autoscaler discovery.
- The bundled `cluster_addons`: CoreDNS, kube-proxy, VPC CNI, EKS Pod Identity
  Agent (the last two installed `before_compute`).
- IRSA enabled and an OIDC provider exported as outputs.
- Two access entries: `operator` (cluster-admin) and `jenkins`
  (namespace-scoped Edit on `weather-staging` and `weather-prod`).
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

  node_instance_types = ["t3.medium"]
  node_min_size       = 2
  node_max_size       = 10
  node_desired_size   = 2

  tags = {
    Project     = "max-weather"
    Environment = "poc"
    ManagedBy   = "terraform"
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
| `node_instance_types` | EC2 instance types for the default node group. | `list(string)` | `["t3.medium"]` | no |
| `node_min_size` | Minimum nodes in the default node group. | `number` | `2` | no |
| `node_max_size` | Maximum nodes in the default node group. | `number` | `10` | no |
| `node_desired_size` | Initial desired node count. | `number` | `2` | no |
| `node_disk_size` | Root EBS volume size in GiB per node. | `number` | `20` | no |
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
