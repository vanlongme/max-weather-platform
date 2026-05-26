# EKS Module

Self-contained EKS module provisions a full cluster environment without upstream dependencies. It owns all resources from control plane to node groups, Fargate profiles, and Karpenter scaffolding. The implementation is split across per-component files for clarity and maintainability. This module is a standalone product that directly manages AWS EKS resources, ensuring consistent configurations and simplified state management.

## Features
- **Cluster**: EKS control plane with public/private API access and CloudWatch logging.
- **Node Groups**: Managed node groups with customizable AMI types, instance types, and scaling.
- **Fargate**: Native Fargate profiles for serverless pod execution.
- **Karpenter**: IAM roles, SQS queue, and EventBridge rules for node auto-provisioning.
- **Security**: Dedicated KMS keys for cluster encryption and EBS volume encryption.
- **Access Control**: Caller-composed access entries via `var.access_entries` — module ships zero built-in entries; caller owns the full map.
- **Identity**: Pod Identity preferred for new workloads; OIDC provider supported for legacy IRSA.
- **Addons**: Managed EKS addons (VPC CNI, CoreDNS, kube-proxy, EBS/EFS CSI) with Pod Identity integration.

## Module Components
| File | Resources |
|------|-----------|
| `access_entries.tf` | `aws_eks_access_entry`, `aws_eks_access_policy_association` |
| `addons.tf` | `aws_eks_addon` (CoreDNS, kube-proxy, VPC CNI, Pod Identity Agent, EBS CSI, EFS CSI) |
| `cloudwatch.tf` | `aws_cloudwatch_log_group` (control plane logs) |
| `main.tf` | `aws_eks_cluster` (primary resource — the module's main deliverable) |
| `data.tf` | All `data` blocks for AWS environment discovery |
| `fargate.tf` | `aws_eks_fargate_profile` |
| `iam.tf` | `aws_iam_role` (cluster, node, fargate, ebs_csi, efs_csi) + policy attachments |
| `karpenter.tf` | `aws_iam_role` (controller + node), `aws_sqs_queue`, `aws_cloudwatch_event_rule` (x4), `aws_iam_instance_profile` |
| `kms.tf` | `aws_kms_key` (cluster + EBS volumes), `aws_kms_alias` |
| `locals.tf` | All `locals` blocks for string manipulation and logic |
| `main.tf` | `aws_eks_node_group` (LT auto-managed by EKS — no `aws_launch_template` resource) |
| `oidc.tf` | `aws_iam_openid_connect_provider` |
| `outputs.tf` | All module `output` blocks |
| `pod_identity.tf` | `aws_eks_pod_identity_association` |
| `security_group.tf` | `aws_security_group` (nodes), `aws_security_group_rule` |
| `variables.tf` | All module `variable` blocks |
| `versions.tf` | Terraform and provider version constraints |

## Usage

### Minimal Usage
```hcl
module "eks" {
  source = "../../modules/eks"

  name           = "poc-max-weather"
  vpc_id         = module.networking.vpc_id
  subnet_ids     = module.networking.public_subnet_ids
  allowed_cidrs  = ["203.0.113.10/32"]

  access_entries = {
    operator = {
      principal_arn = data.aws_caller_identity.current.arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
}
```

### Full Example (Fargate + Karpenter)
```hcl
module "eks" {
  source = "../../modules/eks"

  name           = "poc-max-weather"
  vpc_id         = module.networking.vpc_id
  subnet_ids     = module.networking.public_subnet_ids
  allowed_cidrs  = ["203.0.113.10/32"]

  access_entries = {
    operator = {
      principal_arn = data.aws_caller_identity.current.arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
    readonly = {
      principal_arn = "arn:aws:iam::123456789012:role/AuditReadOnly"
      policy_associations = {
        view = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  fargate_profiles = {
    kube-system = {
      selectors = [{ namespace = "kube-system" }]
    }
  }

  karpenter_create_pod_identity_association = true
  karpenter_node_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:__AWS_PARTITION__:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = {
    Environment = "poc"
    Project     = "max-weather"
  }
}
```

## Inputs

### Core
| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | n/a | Name prefix applied to every resource. Cluster name becomes `<name><suffix>`. |
| `cluster_name_suffix` | `string` | `"-cluster"` | Suffix appended to `name` for the EKS cluster. |
| `cluster_version` | `string` | `"1.34"` | Kubernetes version for the EKS cluster. |
| `vpc_id` | `string` | n/a | VPC ID where the cluster lives. |
| `subnet_ids` | `list(string)` | n/a | Subnet IDs for node groups and control plane ENIs. |
| `allowed_cidrs` | `list(string)` | n/a | CIDRs allowed to reach public EKS API. `0.0.0.0/0` is forbidden. |
| `node_group_name_separator` | `string` | `"-"` | Separator between `name` and group key. |

### KMS
| Name | Type | Default | Description |
|------|------|---------|-------------|
| `kms_deletion_window_days` | `number` | `30` | Deletion window for KMS keys (7-30 days). |
| `kms_enable_key_rotation` | `bool` | `true` | Whether to enable automatic annual key rotation for KMS keys. |

### Cluster
| Name | Type | Default | Description |
|------|------|---------|-------------|
| `authentication_mode` | `string` | `"API_AND_CONFIG_MAP"` | EKS access mode (API, ConfigMap, or both). |
| `cluster_upgrade_support_type` | `string` | `"STANDARD"` | EKS upgrade support type. STANDARD = auto-upgrade at end of standard support (14 months, no fee). EXTENDED = paid extended window. |
| `enable_zonal_shift` | `bool` | `false` | Enable ARC zonal shift on the cluster. |
| `enable_deletion_protection` | `bool` | `false` | Prevent accidental cluster deletion. Recommended `true` for production. |
| `enable_auto_mode` | `bool` | `false` | Enable EKS Auto Mode (delegates node provisioning to AWS). |
| `auto_mode_node_pools` | `list(string)` | `["general-purpose","system"]` | Node pool types for Auto Mode. Only relevant when `enable_auto_mode = true`. |
| `node_repair_enabled` | `bool` | `false` | Module-wide default for node auto-repair. Per-group override via `enable_node_repair`. |
| `enable_cluster_creator_admin_permissions` | `bool` | `false` | Grant admin to the IAM principal running apply. |
| `service_ipv4_cidr` | `string` | `null` | IPv4 CIDR for K8s services. Defaults to `172.20.0.0/16`. |
| `endpoint_public_access` | `bool` | `true` | Enable public internet access to EKS API. |
| `endpoint_private_access` | `bool` | `true` | Enable internal VPC access to EKS API. |

### Logging
| Name | Type | Default | Description |
|------|------|---------|-------------|
| `enabled_log_types` | `list(string)` | `["api", "audit", ...]` | Control plane log types to enable. |
| `log_retention_days` | `number` | `7` | Retention for CloudWatch log group. |

### Access
| Name | Type | Default | Description |
|------|------|---------|-------------|
| `access_entries` | `any` | `{}` | Full map of EKS access entries. Caller composes every entry — module ships NO built-ins. Each entry: `{ principal_arn, policy_associations = { <key> = { policy_arn, access_scope = { type, namespaces? } } } }`. |
| `partition_placeholder` | `string` | `"__AWS_PARTITION__"` | Token replaced with actual AWS partition (used by `karpenter_node_additional_policies`). |

### IRSA
| Name | Type | Default | Description |
|------|------|---------|-------------|
| `enable_irsa` | `bool` | `true` | Create OIDC provider for IRSA. |

### Node Groups
| Name | Type | Default | Description |
|------|------|---------|-------------|
| `eks_managed_node_groups` | `map(object)` | `{infra=...}` | Definitions for managed node groups. Supplied map replaces default. Default: single `infra` group (m6i.large, public subnets, min=2 max=10 desired=2, taint role=infra:NoSchedule). |
| `eks_managed_node_group_defaults` | `any` | `{...}` | Defaults applied to all node groups. |
| `cluster_autoscaler_enabled_tag_key` | `string` | `"k8s.io/cluster-autoscaler/enabled"` | Tag key for Cluster Autoscaler discovery. |
| `cluster_autoscaler_enabled_tag_value` | `string` | `"true"` | Tag value for Cluster Autoscaler discovery. |
| `cluster_autoscaler_owned_tag_key_prefix` | `string` | `"k8s.io/cluster-autoscaler/"` | Prefix for cluster-specific autoscaler tag. |
| `cluster_autoscaler_owned_tag_value` | `string` | `"owned"` | Value for the cluster ownership tag. |

### Fargate
| Name | Type | Default | Description |
|------|------|---------|-------------|
| `fargate_profiles` | `map(object)` | `{}` | Definitions for Fargate profiles. Supplied map replaces default. |

### Addons
| Name | Type | Default | Description |
|------|------|---------|-------------|
| `cluster_addons` | `any` | `{...}` | Map of EKS addons to enable. Replaces default. |
| `enable_ebs_csi_addon` | `bool` | `true` | Enable EBS CSI driver addon. |
| `enable_efs_csi_addon` | `bool` | `true` | Enable EFS CSI driver addon. |
| `ebs_csi_addon_version` | `string` | `null` | Version for EBS CSI addon. `null` = latest. |
| `efs_csi_addon_version` | `string` | `null` | Version for EFS CSI addon. `null` = latest. |

### Karpenter
| Name | Type | Default | Description |
|------|------|---------|-------------|
| `karpenter_namespace` | `string` | `"kube-system"` | Namespace where Karpenter controller runs. |
| `karpenter_service_account` | `string` | `"karpenter"` | Service account name for Karpenter. |
| `karpenter_create_pod_identity_association` | `bool` | `true` | Create Pod Identity for Karpenter controller. |
| `karpenter_create_instance_profile` | `bool` | `true` | Create instance profile for Karpenter nodes. |
| `karpenter_iam_role_name_suffix` | `string` | `"-karpenter-controller-role"` | Suffix for controller role. |
| `karpenter_iam_policy_name_suffix` | `string` | `"-karpenter-controller-policy"` | Suffix for controller policy. |
| `karpenter_node_iam_role_name_suffix` | `string` | `"-karpenter-node-role"` | Suffix for node role. |
| `karpenter_queue_name_suffix` | `string` | `"-karpenter-queue"` | Suffix for SQS interruption queue. |
| `karpenter_node_additional_policies` | `map(string)` | `{SSM=...}` | Additional managed policies for nodes. |
| `karpenter_discovery_tag_key` | `string` | `"karpenter.sh/discovery"` | Tag key used for Karpenter auto-discovery. |
| `karpenter_iam_role_use_name_prefix` | `bool` | `false` | Use name prefix for controller role. |
| `karpenter_iam_policy_use_name_prefix` | `bool` | `false` | Use name prefix for controller policy. |
| `karpenter_node_iam_role_use_name_prefix` | `bool` | `false` | Use name prefix for node role. |

### Pod Identity
| Name | Type | Default | Description |
|------|------|---------|-------------|
| `pod_identity_associations` | `map(object)` | `{}` | Map of Pod Identity associations. |

### Tags
| Name | Type | Default | Description |
|------|------|---------|-------------|
| `tags` | `map(string)` | `{}` | Common tags applied to all resources. |

## Outputs

### Cluster
| Name | Description |
|------|-------------|
| `cluster_name` | EKS cluster name. |
| `cluster_endpoint` | API server endpoint URL. |
| `cluster_ca_data` | Base64-encoded cluster CA certificate. |
| `cluster_version` | Kubernetes version. |
| `cluster_security_group_id` | Security group ID managed by EKS. |
| `cluster_kms_key_arn` | ARN of KMS key for cluster envelope encryption (module-created or caller-supplied via `existing_cluster_kms_key_arn`). |
| `cluster_iam_role_arn` | ARN of cluster control plane IAM role. |

### IAM & OIDC
| Name | Description |
|------|-------------|
| `node_iam_role_arn` | ARN of IAM role for managed node groups. |
| `fargate_iam_role_arn` | ARN of IAM pod execution role for Fargate. |
| `oidc_provider_arn` | ARN of the IAM OIDC provider. |
| `oidc_provider_url` | URL of the OIDC provider (without `https://`). |

### Node Groups
| Name | Description |
|------|-------------|
| `node_security_group_id` | Security group ID for worker nodes. |
| `node_group_arns` | Map of managed node group ARNs. |
| `node_group_names` | Map of managed node group names. |
| `ebs_kms_key_arn` | ARN of KMS key for EBS volume encryption on managed/Karpenter nodes (module-created or caller-supplied via `existing_ebs_kms_key_arn`). |

### Fargate
| Name | Description |
|------|-------------|
| `fargate_profile_arns` | Map of Fargate profile ARNs. |

### Addons/CSI
| Name | Description |
|------|-------------|
| `ebs_csi_controller_role_arn` | ARN of EBS CSI controller role (Pod Identity). |
| `efs_csi_controller_role_arn` | ARN of EFS CSI controller role (Pod Identity). |

### Karpenter
| Name | Description |
|------|-------------|
| `karpenter_queue_name` | Name of the Karpenter SQS interruption queue. |
| `karpenter_node_iam_role_arn` | ARN of IAM role for Karpenter nodes. |
| `karpenter_node_iam_role_name` | Name of IAM role for Karpenter nodes. |
| `karpenter_instance_profile_name` | Name of instance profile for Karpenter nodes. |

## Configuration Notes

### Authentication Mode
Default is `API` (recommended by AWS). Transitions are **one-way**:
`CONFIG_MAP` → `API_AND_CONFIG_MAP` → `API`

You **cannot downgrade**. New clusters should use the default `API`. Clusters currently at `API_AND_CONFIG_MAP` must explicitly set `authentication_mode = "API_AND_CONFIG_MAP"` in their tfvars until ready to migrate.

### Auto Mode (Opt-In)
Set `enable_auto_mode = true` to delegate node provisioning, scaling, and patching to AWS EKS Auto Mode. When enabled:
- Cluster receives 4 additional IAM policies (compute, block storage, load balancing, networking)
- `compute_config`, `storage_config`, and `elastic_load_balancing` blocks are added to the cluster
- Managed node groups should be disabled (Auto Mode manages compute)
- Default: `false`

### Node Auto-Repair
Set `node_repair_enabled = true` (module-wide) or `enable_node_repair = true` per node group to enable automatic replacement of unhealthy nodes. Default: `false` (opt-in).

### Infra Node Group + Addon Scheduling
The default `eks_managed_node_groups` ships a single `infra` group (m6i.large, ON_DEMAND, Bottlerocket x86_64, public subnets, min=2 max=10 desired=2) labeled `role=infra` and tainted `role=infra:NoSchedule`. Addon controllers and Jenkins land on this group; workload pods are handled by Karpenter NodePool on private subnets. All four default cluster add-ons are pre-configured to land on this group:

| Addon | Workload kind | `configuration_values` default |
|-------|---------------|--------------------------------|
| `coredns` | Deployment | `nodeSelector: { role: infra }` + matching `role=infra:NoSchedule` toleration |
| `kube-proxy` | DaemonSet | `tolerations: [{ operator: Exists }]` (must run on every node, regardless of taint) |
| `vpc-cni` | DaemonSet | `tolerations: [{ operator: Exists }]` + `env: {}` placeholder (env merged with VPC CNI custom networking flag) |
| `eks-pod-identity-agent` | DaemonSet | `tolerations: [{ operator: Exists }]` |

DaemonSets use `operator: Exists` so they run on every node regardless of taint (kube-proxy and CNI must run everywhere). The CoreDNS Deployment is pinned with a `nodeSelector` so it co-locates with the infra group. Karpenter-provisioned workload nodes carry their own labels/taints and run application pods.

Supplying `var.cluster_addons` REPLACES the default map entirely — re-declare every entry you want kept (the example tfvars file mirrors the module default).

### Bottlerocket Node User Data
For any managed node group whose `ami_type` starts with `BOTTLEROCKET_` (e.g. `BOTTLEROCKET_x86_64`, `BOTTLEROCKET_x86_64_NVIDIA`, `BOTTLEROCKET_ARM_64`, `BOTTLEROCKET_ARM_64_NVIDIA`), the module sets the launch template `user_data` to a base64-encoded TOML document. For non-Bottlerocket AMIs `user_data` is left null so the EKS bootstrap shim for AL2 / AL2023 / Windows continues to run unchanged.

The baseline TOML (`local.default_bottlerocket_user_data`) hardens the node and tunes kubelet/kernel for production:

- `[settings.host-containers.admin]` disabled, `[settings.host-containers.control]` enabled — no host-admin shell; SSM Session Manager remains available for break-glass.
- `[settings.kubernetes]` — `container-log-max-size = "25Mi"` (string), `container-log-max-files = 5` (i32), `registry-qps = 10` (i32), `registry-burst = 20` (i32), `pod-pids-limit = 1024` (i64). Bottlerocket's settings API is strictly typed — string quantities (`25Mi`) MUST be quoted; integer fields (`pod-pids-limit`, `registry-qps`, `registry-burst`, `container-log-max-files`) MUST be bare integers. Quoting an integer field fails first-boot with `early-boot-config[…]: invalid type: string "X", expected i64/i32`. **The legacy key `registry-pull-qps` does not exist** — was renamed to `registry-qps` in Bottlerocket v1.1.0 and is silently ignored if used.
- `[settings.kubernetes.eviction-hard]` — `"memory.available" = "200Mi"`, `"nodefs.available" = "10%"`. The `nodefs` threshold is evaluated against the filesystem backing the kubelet root + container runtime storage. On the default Bottlerocket layout this is the data volume (`/dev/xvdb`, 50 GiB → 10% ≈ 5 GiB free required); on customized layouts where container storage lives elsewhere, override with an explicit byte size (e.g. `"2Gi"`) per group.
- `[settings.kernel.sysctl]` — `net.core.somaxconn = 4096`, `net.ipv4.tcp_max_syn_backlog = 1024`, `fs.inotify.max_user_instances = 8192`, `fs.inotify.max_user_watches = 524288`, `vm.max_map_count = 262144`.

Per node group, `eks_managed_node_groups.<key>.bottlerocket_user_data` (optional string) **fully REPLACES** the baseline — there is no merge. Set the variable when a group needs different sysctls, eviction thresholds, or host-container settings; leave it null to inherit the baseline.

**NEVER set in caller TOML**: `settings.kubernetes.cluster-name`, `api-server`, `cluster-certificate`, `cluster-dns-ip`, or `kube-reserved`. Bottlerocket's `pluto`/`schnauzer` auto-derive these from the EKS-injected instance metadata at first boot; overriding them breaks bootstrap. The module deliberately omits Bottlerocket factory defaults (`kernel.lockdown = "integrity"`, `settings.updates.*-base-url`, image-gc thresholds) so it never pins a stale value if AWS changes them upstream.

Validation: when set, the value must be non-empty TOML (whitespace-only strings are rejected at plan time).

### VPC CNI Custom Networking ("2nd networking")
Set `enable_vpc_cni_custom_networking = true` to:
1. Inject `AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true` and `ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone` into the vpc-cni addon `configuration_values` (deep-merged with any caller-supplied env / tolerations — your tolerations are preserved).
2. Render one `ENIConfig` Custom Resource per AZ from `var.pod_subnet_ids_by_az` using the module's internal `kubectl` provider; ENIConfig name = AZ name; security group = the module-managed node SG.

**Before-compute ordering** (equivalent to the upstream module's `before_compute = true` on vpc-cni): `aws_eks_node_group.this` declares `depends_on = [aws_eks_addon.this, kubectl_manifest.eniconfig]`, so the VPC CNI addon installs and (when custom networking is enabled) the per-AZ ENIConfig CRs are applied **before any node registers**. This guarantees the first node's kubelet sees a matching ENIConfig for its AZ and allocates pod ENIs from the secondary CIDR on first boot — pods never start on the primary range. When custom networking is disabled, `kubectl_manifest.eniconfig`'s `for_each` collapses to `{}` and the dep is a no-op.

Caller is responsible for:
- Provisioning a secondary VPC CIDR + per-AZ pod subnets (see `modules/networking`).
- Ensuring the cluster API server is reachable from the Terraform runner (PrivateLink / VPC peering / public endpoint) — the kubectl provider needs to talk to the cluster during apply.

```hcl
module "eks" {
  source = "../../modules/eks"
  # ...standard inputs...

  enable_vpc_cni_custom_networking = true
  pod_subnet_ids_by_az = {
    "us-east-1a" = "subnet-aaaaaaaa"
    "us-east-1b" = "subnet-bbbbbbbb"
    "us-east-1c" = "subnet-cccccccc"
  }
}
```

## Design Decisions
1. **Self-contained**: No upstream `terraform-aws-modules/eks/aws` dependency. The module owns every resource directly for maximum control and stability.
2. **Per-component file split**: Resources are organized by AWS service area (one per file: `kms.tf`, `iam.tf`, `addons.tf`, etc.) to prevent monolithic file bloat and improve clarity.
3. **Pod Identity preferred**: New workload roles use EKS Pod Identity (`pods.eks.amazonaws.com` trust) as the primary identity mechanism for EKS 1.30+. IRSA OIDC support is retained for legacy compatibility.
4. **Module-managed KMS**: Always creates dedicated KMS keys for the cluster and EBS volumes. No "Bring Your Own Key" input to ensure consistent policies and lifecycle management.
5. **EBS Encryption**: All managed node group volumes are encrypted via a dedicated KMS key. The node IAM role is automatically granted usage rights to this key.
6. **Internal CSI Ownership**: Module internally provisions IAM roles and Pod Identity associations for EBS CSI and EFS CSI drivers.
7. **Default-replace semantics**: All map inputs (node groups, addons, Fargate profiles, etc.) follow a "replace-on-supply" pattern. Supplying any value completely overrides the built-in defaults; re-declare every entry you want kept.
8. **Caller-composed Access Entries**: module ships zero built-in entries; `var.access_entries` is the full map. Caller composes every principal (operator, readonly, workload roles, etc.).
9. **Karpenter Readiness**: Controller uses Pod Identity; node role uses EC2 trust. Provisions SQS queue for interruption handling and 4 EventBridge rules for spot/health/rebalance/state-change events.

## Cross-References
- `envs/poc/` — Integration test composition wiring every module input.

## Deviations from upstream canonical

**Branch**: `feat/private-cluster-hardening` | **Date**: 2026-05-26

### IMDSv2 enforcement on MNG launch template

- **File**: `launch_template.tf` — `resource "aws_launch_template" "node"`
- **Change**: Added `metadata_options` block with `http_tokens = "required"`, `http_put_response_hop_limit = 1`, `instance_metadata_tags = "enabled"`
- **Rationale**: MNG instances ship with IMDSv1 enabled by default. SSRF + container-escape → IMDS credential exfiltration is a known attack vector. MNG addon controllers (CoreDNS, kube-proxy, VPC CNI, EBS/EFS CSI, AWS LB Controller, KEDA, Karpenter, fluent-bit, cluster-autoscaler) use IRSA via OIDC — none require Pod Identity Agent's hop-2 path, so hop=1 is safe here.
- **ADR cross-reference**: Karpenter EC2NodeClass retains `httpPutResponseHopLimit: 2` because Karpenter-provisioned nodes host application pods that use Pod Identity (Pod Identity Agent needs hop=2 to relay credentials via UDS). Split posture: MNG hop=1 (stronger), Karpenter hop=2 (required for Pod Identity).
- **Upstream status**: Not yet in canonical upstream `terraform-modules/`. If upstream adds IMDSv2 enforcement, remove this section and reconcile.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9, < 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.44 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | ~> 1.14 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.45.0 |
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | 1.19.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | 4.3.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_event_rule.karpenter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.karpenter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_log_group.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_eks_access_entry.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry) | resource |
| [aws_eks_access_policy_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_policy_association) | resource |
| [aws_eks_addon.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_addon.efs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_addon.post_node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_addon.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster) | resource |
| [aws_eks_fargate_profile.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_fargate_profile) | resource |
| [aws_eks_node_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group) | resource |
| [aws_eks_pod_identity_association.karpenter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_eks_pod_identity_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_instance_profile.karpenter_node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_openid_connect_provider.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_policy.karpenter_controller_ec2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.karpenter_controller_iam](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ebs_csi_controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.efs_csi_controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.fargate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.karpenter_controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.karpenter_node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.cluster_block_storage_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.cluster_compute_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.cluster_load_balancing_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.cluster_networking_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.cluster_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.cluster_vpc_resource_controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ebs_csi_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.efs_csi_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.fargate_pod_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.karpenter_controller_ec2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.karpenter_controller_iam](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.karpenter_node_additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.karpenter_node_cni](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.karpenter_node_ecr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.karpenter_node_ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.karpenter_node_worker](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_cni_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_ecr_readonly](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_worker_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_alias.ebs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key.ebs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_launch_template.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_security_group.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_sqs_queue.karpenter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue_policy.karpenter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy) | resource |
| [aws_vpc_security_group_egress_rule.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.cluster_from_node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [kubectl_manifest.eniconfig](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_eks_cluster_auth.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_cluster_auth) | data source |
| [aws_iam_policy_document.cluster_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ebs_csi_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ebs_kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.efs_csi_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.fargate_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.karpenter_controller_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.karpenter_controller_ec2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.karpenter_controller_iam](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.karpenter_node_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.karpenter_queue](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.node_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [tls_certificate.cluster](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/data-sources/certificate) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_entries"></a> [access\_entries](#input\_access\_entries) | Full map of EKS access entries to create. Caller supplies the complete map — module ships NO built-in entries. Key = entry name. Each value: { principal\_arn, policy\_associations = { <assoc\_key> = { policy\_arn, access\_scope = { type, namespaces? } } } }. | `any` | `{}` | no |
| <a name="input_allowed_cidrs"></a> [allowed\_cidrs](#input\_allowed\_cidrs) | CIDR blocks allowed to reach the public EKS API endpoint. Ignored when endpoint\_public\_access = false (fully private cluster). May be [] when public access is disabled. | `list(string)` | `[]` | no |
| <a name="input_authentication_mode"></a> [authentication\_mode](#input\_authentication\_mode) | EKS authentication mode. API is the recommended approach (access entries only, no aws-auth ConfigMap). Transitions are ONE-WAY: CONFIG\_MAP -> API\_AND\_CONFIG\_MAP -> API. You cannot downgrade. Clusters migrating from API\_AND\_CONFIG\_MAP must override explicitly; new clusters should use the default API. | `string` | `"API"` | no |
| <a name="input_auto_mode_node_pools"></a> [auto\_mode\_node\_pools](#input\_auto\_mode\_node\_pools) | Node pool types when EKS Auto Mode is enabled. Valid values: general-purpose, system. Only relevant when enable\_auto\_mode = true. | `list(string)` | <pre>[<br/>  "general-purpose",<br/>  "system"<br/>]</pre> | no |
| <a name="input_cluster_addons"></a> [cluster\_addons](#input\_cluster\_addons) | Map of EKS add-ons to enable. 3-phase bootstrap controlled by per-addon `depends_on_node_group` flag: (1) PRE-NODE addons (flag false/absent) install before any node group → vpc-cni MUST be here so the aws-node DaemonSet + custom-networking env vars exist before kubelet registers; (2) node groups launch with depends\_on=[aws\_eks\_addon.this, kubectl\_manifest.eniconfig]; (3) POST-NODE addons (flag true) install after nodes — kube-proxy / eks-pod-identity-agent / coredns + ebs\_csi / efs\_csi. resolve\_conflicts\_on\_create=OVERWRITE and most\_recent=false are pinned per-addon. Default configuration\_values pin add-ons onto the infra node group: CoreDNS (Deployment) gets nodeSelector role=infra plus a matching toleration; vpc-cni / eks-pod-identity-agent (DaemonSets) get tolerations=[{operator: Exists}] so they land on any tainted node. kube-proxy ships with `tolerations: [{operator: Exists}]` natively and its addon schema does NOT accept a `tolerations` key — leave configuration\_values unset. Supplying configuration\_values per add-on overrides the default for that add-on entirely. | `any` | <pre>{<br/>  "coredns": {<br/>    "configuration_values": "{\"nodeSelector\":{\"role\":\"infra\"},\"tolerations\":[{\"key\":\"role\",\"operator\":\"Equal\",\"value\":\"infra\",\"effect\":\"NoSchedule\"}]}",<br/>    "depends_on_node_group": true,<br/>    "most_recent": false,<br/>    "resolve_conflicts_on_create": "OVERWRITE",<br/>    "resolve_conflicts_on_update": "OVERWRITE"<br/>  },<br/>  "eks-pod-identity-agent": {<br/>    "configuration_values": "{\"tolerations\":[{\"operator\":\"Exists\"}]}",<br/>    "depends_on_node_group": true,<br/>    "most_recent": false,<br/>    "resolve_conflicts_on_create": "OVERWRITE",<br/>    "resolve_conflicts_on_update": "OVERWRITE"<br/>  },<br/>  "kube-proxy": {<br/>    "depends_on_node_group": true,<br/>    "most_recent": false,<br/>    "resolve_conflicts_on_create": "OVERWRITE",<br/>    "resolve_conflicts_on_update": "OVERWRITE"<br/>  },<br/>  "vpc-cni": {<br/>    "configuration_values": "{\"env\":{},\"tolerations\":[{\"operator\":\"Exists\"}]}",<br/>    "most_recent": false,<br/>    "resolve_conflicts_on_create": "OVERWRITE",<br/>    "resolve_conflicts_on_update": "OVERWRITE"<br/>  }<br/>}</pre> | no |
| <a name="input_cluster_autoscaler_enabled_tag_key"></a> [cluster\_autoscaler\_enabled\_tag\_key](#input\_cluster\_autoscaler\_enabled\_tag\_key) | Node group tag key signalling that Cluster Autoscaler should consider this ASG. | `string` | `"k8s.io/cluster-autoscaler/enabled"` | no |
| <a name="input_cluster_autoscaler_enabled_tag_value"></a> [cluster\_autoscaler\_enabled\_tag\_value](#input\_cluster\_autoscaler\_enabled\_tag\_value) | Node group tag value for the Cluster Autoscaler enabled tag. | `string` | `"true"` | no |
| <a name="input_cluster_autoscaler_owned_tag_key_prefix"></a> [cluster\_autoscaler\_owned\_tag\_key\_prefix](#input\_cluster\_autoscaler\_owned\_tag\_key\_prefix) | Prefix for the per-cluster Cluster Autoscaler ownership tag. The full EKS cluster name (var.name + var.cluster\_name\_suffix) is appended to form the full key (k8s.io/cluster-autoscaler/<cluster\_name>). | `string` | `"k8s.io/cluster-autoscaler/"` | no |
| <a name="input_cluster_autoscaler_owned_tag_value"></a> [cluster\_autoscaler\_owned\_tag\_value](#input\_cluster\_autoscaler\_owned\_tag\_value) | Tag value applied to k8s.io/cluster-autoscaler/<cluster\_name> on managed node group ASGs. | `string` | `"owned"` | no |
| <a name="input_cluster_name_suffix"></a> [cluster\_name\_suffix](#input\_cluster\_name\_suffix) | Suffix appended to var.name to form the EKS cluster name. | `string` | `"-cluster"` | no |
| <a name="input_cluster_upgrade_support_type"></a> [cluster\_upgrade\_support\_type](#input\_cluster\_upgrade\_support\_type) | EKS upgrade support type. STANDARD = auto-upgrade at end of standard support window (14 months, no extra fee). EXTENDED = opt-in to 12-month extended support (additional cost). Recommended: STANDARD. | `string` | `"STANDARD"` | no |
| <a name="input_cluster_version"></a> [cluster\_version](#input\_cluster\_version) | Kubernetes version for the EKS cluster. | `string` | `"1.34"` | no |
| <a name="input_ebs_csi_addon_configuration_values"></a> [ebs\_csi\_addon\_configuration\_values](#input\_ebs\_csi\_addon\_configuration\_values) | Raw JSON string passed to the aws-ebs-csi-driver addon `configuration_values`. Default pins the EBS CSI controller Deployment onto the infra node group (nodeSelector role=infra + matching toleration) and tolerates any taint on the ebs-csi-node DaemonSet so it lands on every node. REPLACE semantics: supplying a value fully replaces the default. Set to null to leave addon defaults untouched. | `string` | `"{\"controller\":{\"nodeSelector\":{\"role\":\"infra\"},\"tolerations\":[{\"key\":\"role\",\"operator\":\"Equal\",\"value\":\"infra\",\"effect\":\"NoSchedule\"}]},\"node\":{\"tolerations\":[{\"operator\":\"Exists\"}]}}"` | no |
| <a name="input_ebs_csi_addon_version"></a> [ebs\_csi\_addon\_version](#input\_ebs\_csi\_addon\_version) | Version of the EBS CSI driver addon. Null = use latest compatible version. | `string` | `null` | no |
| <a name="input_efs_csi_addon_configuration_values"></a> [efs\_csi\_addon\_configuration\_values](#input\_efs\_csi\_addon\_configuration\_values) | Raw JSON string passed to the aws-efs-csi-driver addon `configuration_values`. Default pins the EFS CSI controller Deployment onto the infra node group (nodeSelector role=infra + matching toleration) and tolerates any taint on the efs-csi-node DaemonSet so it lands on every node. REPLACE semantics: supplying a value fully replaces the default. Set to null to leave addon defaults untouched. | `string` | `"{\"controller\":{\"nodeSelector\":{\"role\":\"infra\"},\"tolerations\":[{\"key\":\"role\",\"operator\":\"Equal\",\"value\":\"infra\",\"effect\":\"NoSchedule\"}]},\"node\":{\"tolerations\":[{\"operator\":\"Exists\"}]}}"` | no |
| <a name="input_efs_csi_addon_version"></a> [efs\_csi\_addon\_version](#input\_efs\_csi\_addon\_version) | Version of the EFS CSI driver addon. Null = use latest compatible version. | `string` | `null` | no |
| <a name="input_eks_managed_node_group_defaults"></a> [eks\_managed\_node\_group\_defaults](#input\_eks\_managed\_node\_group\_defaults) | Defaults applied to every managed node group. Per-group overrides win. enable\_monitoring and use\_latest\_ami\_release\_version are pinned here to preserve v20 behavior after the v21 default flips (true->false and false->true respectively). | `any` | <pre>{<br/>  "attach_cluster_primary_security_group": false,<br/>  "enable_monitoring": true,<br/>  "use_latest_ami_release_version": false<br/>}</pre> | no |
| <a name="input_eks_managed_node_groups"></a> [eks\_managed\_node\_groups](#input\_eks\_managed\_node\_groups) | Map of EKS managed node group definitions, keyed by node group name. Module always creates a per-group aws\_launch\_template (see launch\_template.tf) and wires it into the node group — native disk\_size is NOT used; configure disk via block\_device\_mappings instead. ami\_release\_version = null (default) lets EKS pick the latest AMI release matching the cluster's Kubernetes version for the chosen ami\_type. Default group is a single t3.medium 'infra' Bottlerocket worker tainted role=infra:NoSchedule (cluster addon controllers tolerate it; Karpenter handles workload scale-out), with the Bottlerocket dual-volume layout: 4GiB gp3 OS root at /dev/xvda + 50GiB gp3 data partition at /dev/xvdb. All volumes encrypted with the module/BYO EBS KMS key. `bottlerocket_user_data` (string, optional): raw TOML applied verbatim as base64-encoded launch template user\_data for Bottlerocket AMI types ONLY (ami\_type matching prefix `BOTTLEROCKET_`). REPLACE semantics — supplying a value fully replaces the module's `local.default_bottlerocket_user_data` baseline. null (default) → baseline applied. Ignored for non-Bottlerocket AMI types (EKS adds the AL2/AL2023 bootstrap shim itself). NEVER set in caller TOML: `settings.kubernetes.cluster-name`, `api-server`, `cluster-certificate`, `cluster-dns-ip` (pluto/schnauzer auto-derive at first boot — overriding breaks bootstrap); `settings.kubernetes.kube-reserved` (schnauzer auto-calcs from max-pods). | <pre>map(object({<br/>    create                     = optional(bool, true)<br/>    name                       = optional(string)<br/>    instance_types             = optional(list(string), ["t3.medium"])<br/>    min_size                   = optional(number, 1)<br/>    max_size                   = optional(number, 10)<br/>    desired_size               = optional(number, 1)<br/>    capacity_type              = optional(string, "ON_DEMAND")<br/>    ami_type                   = optional(string, "BOTTLEROCKET_x86_64")<br/>    ami_release_version        = optional(string)<br/>    labels                     = optional(map(string), {})<br/>    taints                     = optional(map(object({ key = string, value = optional(string), effect = string })), {})<br/>    tags                       = optional(map(string), {})<br/>    iam_role_use_name_prefix   = optional(bool, false)<br/>    enable_node_repair         = optional(bool)<br/>    max_unavailable_percentage = optional(number, 33)<br/>    enable_monitoring          = optional(bool, true)<br/>    bottlerocket_user_data     = optional(string)<br/>    # block_device_mappings: map key = mapping name (free-form). device_name<br/>    # defaults to /dev/xvda (BOTTLEROCKET_x86_64 / AL2 root); Bottlerocket data<br/>    # volume uses a second entry with /dev/xvdb. iops/throughput only apply to<br/>    # volume_type io1/io2/gp3. kms_key_id = null → local.ebs_kms_key_arn.<br/>    block_device_mappings = optional(map(object({<br/>      device_name           = optional(string, "/dev/xvda")<br/>      volume_size           = optional(number, 20)<br/>      volume_type           = optional(string, "gp3")<br/>      iops                  = optional(number)<br/>      throughput            = optional(number)<br/>      encrypted             = optional(bool, true)<br/>      delete_on_termination = optional(bool, true)<br/>      kms_key_id            = optional(string)<br/>    })), {})<br/>  }))</pre> | <pre>{<br/>  "infra": {<br/>    "ami_type": "BOTTLEROCKET_x86_64",<br/>    "block_device_mappings": {<br/>      "data": {<br/>        "device_name": "/dev/xvdb",<br/>        "volume_size": 50,<br/>        "volume_type": "gp3"<br/>      },<br/>      "root": {<br/>        "device_name": "/dev/xvda",<br/>        "volume_size": 4,<br/>        "volume_type": "gp3"<br/>      }<br/>    },<br/>    "desired_size": 1,<br/>    "instance_types": [<br/>      "t3.medium"<br/>    ],<br/>    "labels": {<br/>      "role": "infra"<br/>    },<br/>    "max_size": 10,<br/>    "min_size": 2,<br/>    "taints": {<br/>      "infra": {<br/>        "effect": "NO_SCHEDULE",<br/>        "key": "role",<br/>        "value": "infra"<br/>      }<br/>    }<br/>  }<br/>}</pre> | no |
| <a name="input_enable_auto_mode"></a> [enable\_auto\_mode](#input\_enable\_auto\_mode) | Whether to enable EKS Auto Mode on the cluster. Auto Mode delegates node provisioning, scaling, and patching to AWS. Requires additional cluster IAM policies (created conditionally). Default false — opt-in only. | `bool` | `false` | no |
| <a name="input_enable_cluster_creator_admin_permissions"></a> [enable\_cluster\_creator\_admin\_permissions](#input\_enable\_cluster\_creator\_admin\_permissions) | Whether the IAM principal that runs `terraform apply` is auto-granted cluster-admin via an implicit access entry. Disabled so the explicit operator access entry is the single source of truth. | `bool` | `false` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | Whether to enable deletion protection on the EKS cluster. When true, the cluster cannot be deleted via Terraform destroy or the AWS console until protection is explicitly disabled. Recommended true for production. | `bool` | `false` | no |
| <a name="input_enable_ebs_csi_addon"></a> [enable\_ebs\_csi\_addon](#input\_enable\_ebs\_csi\_addon) | Whether to create the EBS CSI driver addon with a module-managed IAM role via Pod Identity. | `bool` | `true` | no |
| <a name="input_enable_efs_csi_addon"></a> [enable\_efs\_csi\_addon](#input\_enable\_efs\_csi\_addon) | Whether to create the EFS CSI driver addon with a module-managed IAM role via Pod Identity. | `bool` | `true` | no |
| <a name="input_enable_irsa"></a> [enable\_irsa](#input\_enable\_irsa) | Whether to create the OIDC provider required by IAM Roles for Service Accounts. | `bool` | `true` | no |
| <a name="input_enable_vpc_cni_custom_networking"></a> [enable\_vpc\_cni\_custom\_networking](#input\_enable\_vpc\_cni\_custom\_networking) | Enable VPC CNI custom networking ('2nd networking'). Module injects AWS\_VPC\_K8S\_CNI\_CUSTOM\_NETWORK\_CFG=true and ENI\_CONFIG\_LABEL\_DEF=topology.kubernetes.io/zone into the vpc-cni addon configuration\_values AND renders one ENIConfig CR per AZ (via kubectl provider) keyed on var.pod\_subnet\_ids\_by\_az. Caller still must provision the secondary VPC CIDR + per-AZ pod subnets (see networking module). Assumes cluster API server is reachable from the Terraform runner. See https://docs.aws.amazon.com/eks/latest/userguide/cni-custom-network.html | `bool` | `false` | no |
| <a name="input_enable_zonal_shift"></a> [enable\_zonal\_shift](#input\_enable\_zonal\_shift) | Whether to enable ARC zonal shift on the EKS cluster. Allows shifting traffic away from an impaired AZ without DNS changes. Requires ARC zonal shift to be configured in the account. | `bool` | `false` | no |
| <a name="input_enabled_log_types"></a> [enabled\_log\_types](#input\_enabled\_log\_types) | EKS control-plane log types to ship to CloudWatch Logs. | `list(string)` | <pre>[<br/>  "api",<br/>  "audit",<br/>  "authenticator",<br/>  "controllerManager",<br/>  "scheduler"<br/>]</pre> | no |
| <a name="input_endpoint_private_access"></a> [endpoint\_private\_access](#input\_endpoint\_private\_access) | Whether the EKS API server endpoint is reachable from inside the VPC. | `bool` | `true` | no |
| <a name="input_endpoint_public_access"></a> [endpoint\_public\_access](#input\_endpoint\_public\_access) | Whether the EKS API server endpoint is reachable from the public internet (restricted further by var.allowed\_cidrs). | `bool` | `true` | no |
| <a name="input_existing_cluster_kms_key_arn"></a> [existing\_cluster\_kms\_key\_arn](#input\_existing\_cluster\_kms\_key\_arn) | ARN of an existing customer-managed KMS key to use for EKS cluster envelope (secrets) encryption. When null (default), the module creates and owns aws\_kms\_key.cluster + alias. When set, the module skips key creation and consumes the supplied ARN — the alias is NOT created either. | `string` | `null` | no |
| <a name="input_existing_ebs_kms_key_arn"></a> [existing\_ebs\_kms\_key\_arn](#input\_existing\_ebs\_kms\_key\_arn) | ARN of an existing customer-managed KMS key to use for EBS volume encryption on managed/Karpenter nodes. When null (default), the module creates and owns aws\_kms\_key.ebs + alias + key policy. The module-managed policy grants: (a) node + karpenter\_node IAM roles Encrypt/Decrypt/ReEncrypt*/GenerateDataKey*/DescribeKey, (b) the AWSServiceRoleForAutoScaling SLR (NOT the autoscaling.amazonaws.com Service principal — that form is a silent no-op for SLR services) the same 5 actions plus CreateGrant conditioned on kms:GrantIsForAWSResource=true. When set, the caller MUST replicate all three grants on the BYO key (see node\_iam\_role\_arn / karpenter\_node\_iam\_role\_arn outputs). Reference: https://docs.aws.amazon.com/autoscaling/ec2/userguide/key-policy-requirements-EBS-encryption.html | `string` | `null` | no |
| <a name="input_fargate_profiles"></a> [fargate\_profiles](#input\_fargate\_profiles) | Map of Fargate profile definitions. Each entry creates an aws\_eks\_fargate\_profile. Default empty — no Fargate by default. Map key = profile name. Each value has a 'selectors' list of objects with 'namespace' (required) and 'labels' (optional map). | <pre>map(object({<br/>    selectors = list(object({<br/>      namespace = string<br/>      labels    = optional(map(string), {})<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_karpenter_create_instance_profile"></a> [karpenter\_create\_instance\_profile](#input\_karpenter\_create\_instance\_profile) | Whether the upstream karpenter sub-module should create the EC2 instance profile attached to Karpenter-provisioned nodes. | `bool` | `true` | no |
| <a name="input_karpenter_create_pod_identity_association"></a> [karpenter\_create\_pod\_identity\_association](#input\_karpenter\_create\_pod\_identity\_association) | Whether the upstream karpenter sub-module should create an EKS Pod Identity association for the controller IAM role. | `bool` | `true` | no |
| <a name="input_karpenter_discovery_tag_key"></a> [karpenter\_discovery\_tag\_key](#input\_karpenter\_discovery\_tag\_key) | Tag key consumed by Karpenter EC2NodeClass.securityGroupSelectorTerms / subnetSelectorTerms (and applied to karpenter sub-module resources). Tag value is the full EKS cluster name (var.name + var.cluster\_name\_suffix). | `string` | `"karpenter.sh/discovery"` | no |
| <a name="input_karpenter_iam_policy_name_suffix"></a> [karpenter\_iam\_policy\_name\_suffix](#input\_karpenter\_iam\_policy\_name\_suffix) | Suffix appended to var.name to form the karpenter controller IAM policy name. | `string` | `"-karpenter-controller-policy"` | no |
| <a name="input_karpenter_iam_policy_use_name_prefix"></a> [karpenter\_iam\_policy\_use\_name\_prefix](#input\_karpenter\_iam\_policy\_use\_name\_prefix) | Whether the upstream karpenter sub-module treats iam\_policy\_name as a name\_prefix instead of a fixed name. | `bool` | `false` | no |
| <a name="input_karpenter_iam_role_name_suffix"></a> [karpenter\_iam\_role\_name\_suffix](#input\_karpenter\_iam\_role\_name\_suffix) | Suffix appended to var.name to form the karpenter controller IAM role name. | `string` | `"-karpenter-controller-role"` | no |
| <a name="input_karpenter_iam_role_use_name_prefix"></a> [karpenter\_iam\_role\_use\_name\_prefix](#input\_karpenter\_iam\_role\_use\_name\_prefix) | Whether the upstream karpenter sub-module treats iam\_role\_name as a name\_prefix instead of a fixed name. | `bool` | `false` | no |
| <a name="input_karpenter_namespace"></a> [karpenter\_namespace](#input\_karpenter\_namespace) | Namespace where Karpenter controller runs. | `string` | `"kube-system"` | no |
| <a name="input_karpenter_node_additional_policies"></a> [karpenter\_node\_additional\_policies](#input\_karpenter\_node\_additional\_policies) | Additional managed-policy ARNs (keyed by short name) attached to the karpenter node IAM role. The literal var.partition\_placeholder is substituted with data.aws\_partition.current.partition at apply time. Default: SSM Session Manager access. | `map(string)` | <pre>{<br/>  "AmazonSSMManagedInstanceCore": "arn:__AWS_PARTITION__:iam::aws:policy/AmazonSSMManagedInstanceCore"<br/>}</pre> | no |
| <a name="input_karpenter_node_iam_role_name_suffix"></a> [karpenter\_node\_iam\_role\_name\_suffix](#input\_karpenter\_node\_iam\_role\_name\_suffix) | Suffix appended to var.name to form the karpenter node IAM role name. | `string` | `"-karpenter-node-role"` | no |
| <a name="input_karpenter_node_iam_role_use_name_prefix"></a> [karpenter\_node\_iam\_role\_use\_name\_prefix](#input\_karpenter\_node\_iam\_role\_use\_name\_prefix) | Whether the upstream karpenter sub-module treats node\_iam\_role\_name as a name\_prefix instead of a fixed name. | `bool` | `false` | no |
| <a name="input_karpenter_queue_name_suffix"></a> [karpenter\_queue\_name\_suffix](#input\_karpenter\_queue\_name\_suffix) | Suffix appended to var.name to form the karpenter SQS queue name (receives EC2 spot interruption / health events). | `string` | `"-karpenter-queue"` | no |
| <a name="input_karpenter_service_account"></a> [karpenter\_service\_account](#input\_karpenter\_service\_account) | Service account name for Karpenter controller. | `string` | `"karpenter"` | no |
| <a name="input_kms_deletion_window_days"></a> [kms\_deletion\_window\_days](#input\_kms\_deletion\_window\_days) | Number of days before KMS key deletion after removal. Range 7-30. | `number` | `30` | no |
| <a name="input_kms_enable_key_rotation"></a> [kms\_enable\_key\_rotation](#input\_kms\_enable\_key\_rotation) | Whether to enable automatic annual key rotation for KMS keys. | `bool` | `true` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch log retention in days for EKS control-plane logs. | `number` | `7` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix applied to every resource (typically the master\_prefix from the composition, e.g. 'poc-max-weather'). The EKS cluster itself is named <var.name><var.cluster\_name\_suffix>. | `string` | n/a | yes |
| <a name="input_node_group_name_separator"></a> [node\_group\_name\_separator](#input\_node\_group\_name\_separator) | Separator placed between var.name and the node-group map key when synthesizing the upstream `name` argument. | `string` | `"-"` | no |
| <a name="input_node_repair_enabled"></a> [node\_repair\_enabled](#input\_node\_repair\_enabled) | Whether to enable automatic node repair on managed node groups. When enabled, EKS detects and replaces unhealthy nodes automatically. Default false — opt-in. Per-group override via enable\_node\_repair in eks\_managed\_node\_groups. | `bool` | `false` | no |
| <a name="input_node_security_group_additional_rules"></a> [node\_security\_group\_additional\_rules](#input\_node\_security\_group\_additional\_rules) | Override node security group rules. REPLACE semantics: when ingress or egress is non-null, the caller-supplied map fully replaces the canonical default set (cluster→node 443/10250/4443/6443/8443/9443; self CoreDNS 53 tcp+udp + ephemeral 1025-65535; egress 0.0.0.0/0). Set ingress=null and/or egress=null to keep defaults. Each rule supports: description, ip\_protocol, from\_port, to\_port, cidr\_ipv4 (or source='cluster'\|'self' for SG-referenced rules; egress also supports referenced\_security\_group\_id). | <pre>object({<br/>    ingress = optional(map(any))<br/>    egress  = optional(map(any))<br/>  })</pre> | `{}` | no |
| <a name="input_partition_placeholder"></a> [partition\_placeholder](#input\_partition\_placeholder) | Literal placeholder token in cluster access policy ARN templates substituted with data.aws\_partition.current.partition at apply time. | `string` | `"__AWS_PARTITION__"` | no |
| <a name="input_pod_identity_associations"></a> [pod\_identity\_associations](#input\_pod\_identity\_associations) | Map of EKS Pod Identity associations to create against this cluster. Keyed by short name (typically the IAM role's map key in the iam module). Each entry binds a Kubernetes ServiceAccount (namespace + service\_account) to an IAM role ARN. Feed module.iam.pod\_identity\_role\_bindings straight in. | <pre>map(object({<br/>    namespace            = string<br/>    service_account      = string<br/>    role_arn             = string<br/>    disable_session_tags = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_pod_subnet_ids_by_az"></a> [pod\_subnet\_ids\_by\_az](#input\_pod\_subnet\_ids\_by\_az) | Map of AZ name -> pod subnet ID for VPC CNI custom networking. Required when enable\_vpc\_cni\_custom\_networking = true. One entry per AZ; the AZ name is used verbatim as the ENIConfig CR name (matches ENI\_CONFIG\_LABEL\_DEF=topology.kubernetes.io/zone). | `map(string)` | `{}` | no |
| <a name="input_service_ipv4_cidr"></a> [service\_ipv4\_cidr](#input\_service\_ipv4\_cidr) | IPv4 CIDR block to assign to Kubernetes service addresses. Leave null to let EKS choose (default 172.20.0.0/16). | `string` | `null` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs for managed node groups and control plane ENIs. POC topology passes the public subnet IDs here; production should pass private subnet IDs. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Common tags applied to all resources. | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where the cluster lives. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_ca_data"></a> [cluster\_ca\_data](#output\_cluster\_ca\_data) | Base64-encoded certificate authority data for the cluster. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | EKS cluster API server endpoint. |
| <a name="output_cluster_iam_role_arn"></a> [cluster\_iam\_role\_arn](#output\_cluster\_iam\_role\_arn) | ARN of the IAM role attached to the EKS cluster control plane. |
| <a name="output_cluster_kms_key_arn"></a> [cluster\_kms\_key\_arn](#output\_cluster\_kms\_key\_arn) | ARN of the KMS key used for EKS cluster envelope encryption (module-created or caller-supplied via var.existing\_cluster\_kms\_key\_arn). |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | EKS cluster name. |
| <a name="output_cluster_oidc_issuer_url"></a> [cluster\_oidc\_issuer\_url](#output\_cluster\_oidc\_issuer\_url) | OIDC issuer URL for the EKS cluster. |
| <a name="output_cluster_security_group_id"></a> [cluster\_security\_group\_id](#output\_cluster\_security\_group\_id) | Security group ID of the EKS control plane (managed by EKS). |
| <a name="output_cluster_version"></a> [cluster\_version](#output\_cluster\_version) | Kubernetes version of the cluster. |
| <a name="output_ebs_csi_controller_role_arn"></a> [ebs\_csi\_controller\_role\_arn](#output\_ebs\_csi\_controller\_role\_arn) | ARN of the EBS CSI controller IAM role (Pod Identity). Null when enable\_ebs\_csi\_addon = false. |
| <a name="output_ebs_kms_key_arn"></a> [ebs\_kms\_key\_arn](#output\_ebs\_kms\_key\_arn) | ARN of the KMS key used for EBS volume encryption on managed node groups (module-created or caller-supplied via var.existing\_ebs\_kms\_key\_arn). |
| <a name="output_efs_csi_controller_role_arn"></a> [efs\_csi\_controller\_role\_arn](#output\_efs\_csi\_controller\_role\_arn) | ARN of the EFS CSI controller IAM role (Pod Identity). Null when enable\_efs\_csi\_addon = false. |
| <a name="output_fargate_iam_role_arn"></a> [fargate\_iam\_role\_arn](#output\_fargate\_iam\_role\_arn) | ARN of the IAM pod execution role used by Fargate profiles. |
| <a name="output_fargate_profile_arns"></a> [fargate\_profile\_arns](#output\_fargate\_profile\_arns) | Map of Fargate profile ARNs keyed by profile name. |
| <a name="output_karpenter_instance_profile_name"></a> [karpenter\_instance\_profile\_name](#output\_karpenter\_instance\_profile\_name) | Name of the IAM instance profile attached to Karpenter-provisioned nodes. Null when karpenter\_create\_instance\_profile = false. |
| <a name="output_karpenter_node_iam_role_arn"></a> [karpenter\_node\_iam\_role\_arn](#output\_karpenter\_node\_iam\_role\_arn) | ARN of the IAM role assumed by Karpenter-provisioned EC2 nodes. |
| <a name="output_karpenter_node_iam_role_name"></a> [karpenter\_node\_iam\_role\_name](#output\_karpenter\_node\_iam\_role\_name) | Name of the IAM role assumed by Karpenter-provisioned EC2 nodes. |
| <a name="output_karpenter_queue_name"></a> [karpenter\_queue\_name](#output\_karpenter\_queue\_name) | Name of the Karpenter SQS interruption queue. |
| <a name="output_node_group_arns"></a> [node\_group\_arns](#output\_node\_group\_arns) | Map of node group ARNs keyed by node group map key. |
| <a name="output_node_group_names"></a> [node\_group\_names](#output\_node\_group\_names) | Map of node group names keyed by node group map key. |
| <a name="output_node_iam_role_arn"></a> [node\_iam\_role\_arn](#output\_node\_iam\_role\_arn) | ARN of the IAM role attached to managed node group instances. |
| <a name="output_node_security_group_id"></a> [node\_security\_group\_id](#output\_node\_security\_group\_id) | Security group ID attached to managed node group instances. |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | ARN of the IAM OIDC provider for IRSA. |
| <a name="output_oidc_provider_url"></a> [oidc\_provider\_url](#output\_oidc\_provider\_url) | URL of the OIDC provider without https:// prefix (used in IRSA trust policies). |
<!-- END_TF_DOCS -->
