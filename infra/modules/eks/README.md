# EKS Module

Thin wrapper around the upstream
[`terraform-aws-modules/eks/aws`](https://github.com/terraform-aws-modules/terraform-aws-eks)
(v21.20) that provisions:

- An EKS cluster named `${var.name}${var.cluster_name_suffix}` with public + private API endpoints,
  public access locked to `var.allowed_cidrs` (`0.0.0.0/0` is rejected by validation).
- One or more managed node groups driven by the `eks_managed_node_groups` map
  (default: a single `general` group — Bottlerocket x86_64, ON_DEMAND `t3.medium`,
  min 1 / max 10 / desired 1 — tagged for Cluster Autoscaler discovery; serves as
  the init worker that hosts cluster add-ons + Karpenter while Karpenter scales
  workload nodes on top).
- The bundled `cluster_addons`: CoreDNS, kube-proxy, VPC CNI, EKS Pod Identity
  Agent (the last two installed `before_compute`). Override via `cluster_addons`.
- IRSA enabled and an OIDC provider exported as outputs.
- Two built-in access entries: `operator` (cluster-admin) and `jenkins`
  (namespace-scoped Edit on the namespaces in `var.jenkins_access_namespaces`,
  default `["weather-staging", "weather-prod"]`). Additional entries can be
  merged in via `access_entries`.
- Karpenter scaffolding via the upstream
  [`karpenter` sub-module](https://github.com/terraform-aws-modules/terraform-aws-eks/tree/master/modules/karpenter):
  controller IAM role + policy (via **EKS Pod Identity** as of v21 — no IRSA
  ServiceAccount annotation needed), node IAM role + instance profile, SQS
  queue, and EventBridge rules. The actual Karpenter Helm chart and
  `EC2NodeClass` / `NodePool` objects live under `k8s/helm/karpenter/`.

## Resource naming

Every resource name is derived from `var.name` plus a per-resource suffix.
With `var.name = "poc-max-weather"` and the default suffixes:

| Resource                              | Name                                          |
|---------------------------------------|-----------------------------------------------|
| EKS cluster                           | `poc-max-weather-cluster`                     |
| Managed node group (`general` key)    | `poc-max-weather-general`                     |
| Karpenter controller IAM role         | `poc-max-weather-karpenter-controller-role`   |
| Karpenter controller IAM policy       | `poc-max-weather-karpenter-controller-policy` |
| Karpenter node IAM role               | `poc-max-weather-karpenter-node-role`         |
| Karpenter SQS queue                   | `poc-max-weather-karpenter-queue`             |

Override any suffix via the corresponding `*_suffix` variable
(e.g. `cluster_name_suffix = "-eks"` → `poc-max-weather-eks`).

## Usage

```hcl
module "eks" {
  source = "../../modules/eks"

  name            = "poc-max-weather"
  cluster_version = "1.34"

  vpc_id     = module.networking.vpc_id
  subnet_ids = module.networking.public_subnet_ids # POC: public; prod: private

  allowed_cidrs             = ["203.0.113.10/32"]
  operator_principal_arn    = data.aws_caller_identity.current.arn
  jenkins_role_arn          = module.iam.jenkins_role_arn
  pod_identity_associations = module.iam.pod_identity_role_bindings

  eks_managed_node_groups = {
    general = {
      instance_types = ["t3.medium"]
      ami_type       = "BOTTLEROCKET_x86_64"
      min_size       = 1
      max_size       = 10
      desired_size   = 1
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
| `name` | Name prefix for every resource (typically `local.master_prefix`). | `string` | n/a | yes |
| `cluster_name_suffix` | Suffix appended to `var.name` for the EKS cluster name. | `string` | `"-cluster"` | no |
| `cluster_version` | Kubernetes version. | `string` | `"1.34"` | no |
| `vpc_id` | VPC ID for the cluster. | `string` | n/a | yes |
| `subnet_ids` | Subnet IDs for nodes + control plane ENIs (POC: public, prod: private). | `list(string)` | n/a | yes |
| `allowed_cidrs` | CIDRs allowed to reach the public EKS API endpoint. `0.0.0.0/0` is rejected. | `list(string)` | n/a | yes |
| `operator_principal_arn` | IAM principal granted cluster-admin via access entry. | `string` | n/a | yes |
| `jenkins_role_arn` | Jenkins IAM role granted Edit on the namespaces in `var.jenkins_access_namespaces`. Empty -> jenkins access entry omitted. | `string` | `""` | no |
| `jenkins_access_namespaces` | Kubernetes namespaces granted Edit access for `var.jenkins_role_arn`. | `list(string)` | `["weather-staging", "weather-prod"]` | no |
| `pod_identity_associations` | Map of EKS Pod Identity associations to create on this cluster (key = arbitrary id; value = `{ namespace, service_account, role_arn }`). Typically fed from `module.iam.pod_identity_role_bindings`. | `map(object({namespace=string, service_account=string, role_arn=string}))` | `{}` | no |
| `eks_managed_node_groups` | Map of EKS managed node group definitions, keyed by group name. Passed through to the upstream `eks_managed_node_groups` input. | `map(object)` | single `general` group | no |
| `eks_managed_node_group_defaults` | Defaults applied to every managed node group; per-group overrides win. | `any` | `{ attach_cluster_primary_security_group = false, enable_monitoring = true, use_latest_ami_release_version = false }` | no |
| `cluster_addons` | Map of EKS add-ons to enable. Passed through to the upstream `addons` input. | `any` | CoreDNS / kube-proxy / VPC CNI / Pod Identity Agent | no |
| `access_entries` | Extra access entries merged after the built-in operator + jenkins entries (user-supplied entries win on key collision). | `any` | `{}` | no |
| `tags` | Common tags applied to all resources. | `map(string)` | `{}` | no |
| `endpoint_public_access` | Whether the EKS API server endpoint is reachable from the public internet (restricted further by `var.allowed_cidrs`). | `bool` | `true` | no |
| `endpoint_private_access` | Whether the EKS API server endpoint is reachable from inside the VPC. | `bool` | `true` | no |
| `enabled_log_types` | EKS control-plane log types shipped to CloudWatch Logs. | `list(string)` | `["api","audit","authenticator","controllerManager","scheduler"]` | no |
| `enable_irsa` | Whether to create the OIDC provider required by IRSA. | `bool` | `true` | no |
| `authentication_mode` | EKS access mode. | `string` | `"API_AND_CONFIG_MAP"` | no |
| `enable_cluster_creator_admin_permissions` | Whether the IAM principal that runs `terraform apply` is auto-granted cluster-admin. | `bool` | `false` | no |
| `operator_access_entry_key` | Map key for the operator access entry. | `string` | `"operator"` | no |
| `operator_policy_association_key` | Map key for the policy association under the operator access entry. | `string` | `"admin"` | no |
| `operator_cluster_access_policy_arn_template` | ARN template for the cluster-admin EKS cluster access policy (`__AWS_PARTITION__` substituted). | `string` | `"arn:__AWS_PARTITION__:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"` | no |
| `operator_access_scope_type` | Access scope type for the operator policy association. | `string` | `"cluster"` | no |
| `jenkins_access_entry_key` | Map key for the jenkins access entry. | `string` | `"jenkins"` | no |
| `jenkins_policy_association_key` | Map key for the policy association under the jenkins access entry. | `string` | `"edit"` | no |
| `jenkins_cluster_access_policy_arn_template` | ARN template for the namespace-scoped Edit policy. | `string` | `"arn:__AWS_PARTITION__:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"` | no |
| `jenkins_access_scope_type` | Access scope type for the jenkins policy association. | `string` | `"namespace"` | no |
| `partition_placeholder` | Literal placeholder substituted with `data.aws_partition.current.partition`. | `string` | `"__AWS_PARTITION__"` | no |
| `node_group_name_separator` | Separator between `var.name` and the node-group map key. | `string` | `"-"` | no |
| `cluster_autoscaler_enabled_tag_key` | Node-group tag key signalling Cluster Autoscaler should consider this ASG. | `string` | `"k8s.io/cluster-autoscaler/enabled"` | no |
| `cluster_autoscaler_enabled_tag_value` | Tag value for the Cluster Autoscaler enabled tag. | `string` | `"true"` | no |
| `cluster_autoscaler_owned_tag_key_prefix` | Prefix for the per-cluster Cluster Autoscaler ownership tag. | `string` | `"k8s.io/cluster-autoscaler/"` | no |
| `cluster_autoscaler_owned_tag_value` | Value for `k8s.io/cluster-autoscaler/<cluster_name>`. | `string` | `"owned"` | no |
| `karpenter_discovery_tag_key` | Tag key consumed by Karpenter `EC2NodeClass`. | `string` | `"karpenter.sh/discovery"` | no |
| `karpenter_create_pod_identity_association` | Whether the karpenter sub-module creates an EKS Pod Identity association. | `bool` | `true` | no |
| `karpenter_create_instance_profile` | Whether the karpenter sub-module creates the EC2 instance profile. | `bool` | `true` | no |
| `karpenter_iam_role_name_suffix` | Suffix appended to `var.name` for the karpenter controller IAM role. | `string` | `"-karpenter-controller-role"` | no |
| `karpenter_iam_policy_name_suffix` | Suffix appended to `var.name` for the karpenter controller IAM policy. | `string` | `"-karpenter-controller-policy"` | no |
| `karpenter_iam_role_use_name_prefix` | Whether `iam_role_name` is treated as a name_prefix. | `bool` | `false` | no |
| `karpenter_iam_policy_use_name_prefix` | Whether `iam_policy_name` is treated as a name_prefix. | `bool` | `false` | no |
| `karpenter_node_iam_role_name_suffix` | Suffix appended to `var.name` for the karpenter node IAM role. | `string` | `"-karpenter-node-role"` | no |
| `karpenter_node_iam_role_use_name_prefix` | Whether `node_iam_role_name` is treated as a name_prefix. | `bool` | `false` | no |
| `karpenter_queue_name_suffix` | Suffix appended to `var.name` for the karpenter SQS queue name. | `string` | `"-karpenter-queue"` | no |
| `karpenter_node_additional_policies` | Managed-policy ARNs attached to the karpenter node IAM role (`__AWS_PARTITION__` substituted). | `map(string)` | `{ AmazonSSMManagedInstanceCore = "arn:__AWS_PARTITION__:iam::aws:policy/AmazonSSMManagedInstanceCore" }` | no |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_name` | EKS cluster name (`${var.name}${var.cluster_name_suffix}`). |
| `cluster_endpoint` | API server endpoint URL. |
| `cluster_ca_data` | Base64-encoded cluster CA. |
| `cluster_version` | Kubernetes version. |
| `cluster_oidc_issuer_url` | OIDC issuer URL. |
| `oidc_provider_arn` | IAM OIDC provider ARN (for IRSA trust policies). |
| `oidc_provider_url` | OIDC provider URL without `https://` prefix. |
| `cluster_security_group_id` | EKS-managed control plane SG ID. |
| `node_security_group_id` | SG ID attached to managed node group instances. |
| `karpenter_queue_name` | SQS queue name consumed by the Karpenter controller. |
| `karpenter_node_iam_role_arn` | IAM role ARN attached to Karpenter-provisioned nodes. |
| `karpenter_node_iam_role_name` | IAM role name attached to Karpenter-provisioned nodes (referenced from `EC2NodeClass.role`). |
| `karpenter_instance_profile_name` | Instance profile name attached to Karpenter-provisioned nodes. |

## Requirements

| Name | Version |
|------|---------|
| terraform | `>= 1.9, < 2.0` |
| aws | `~> 6.0` |
| upstream `terraform-aws-modules/eks/aws` | `~> 21.20` |
| upstream `terraform-aws-modules/eks/aws//modules/karpenter` | `~> 21.20` |
