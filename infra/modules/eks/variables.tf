variable "name" {
  description = "Name prefix applied to every resource (typically the master_prefix from the composition, e.g. 'poc-max-weather'). The EKS cluster itself is named <var.name><var.cluster_name_suffix>."
  type        = string
}

variable "cluster_name_suffix" {
  description = "Suffix appended to var.name to form the EKS cluster name."
  type        = string
  default     = "-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.34"
}

variable "vpc_id" {
  description = "VPC ID where the cluster lives."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for managed node groups and control plane ENIs. POC topology passes the public subnet IDs here; production should pass private subnet IDs."
  type        = list(string)
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint. Ignored when endpoint_public_access = false (fully private cluster). May be [] when public access is disabled."
  type        = list(string)
  default     = []
}

variable "eks_managed_node_groups" {
  description = "Map of EKS managed node group definitions, keyed by node group name. Module always creates a per-group aws_launch_template (see launch_template.tf) and wires it into the node group — native disk_size is NOT used; configure disk via block_device_mappings instead. ami_release_version = null (default) lets EKS pick the latest AMI release matching the cluster's Kubernetes version for the chosen ami_type. Default group is a single t3.medium 'infra' Bottlerocket worker tainted role=infra:NoSchedule (cluster addon controllers tolerate it; Karpenter handles workload scale-out), with the Bottlerocket dual-volume layout: 4GiB gp3 OS root at /dev/xvda + 50GiB gp3 data partition at /dev/xvdb. All volumes encrypted with the module/BYO EBS KMS key. `bottlerocket_user_data` (string, optional): raw TOML applied verbatim as base64-encoded launch template user_data for Bottlerocket AMI types ONLY (ami_type matching prefix `BOTTLEROCKET_`). REPLACE semantics — supplying a value fully replaces the module's `local.default_bottlerocket_user_data` baseline. null (default) → baseline applied. Ignored for non-Bottlerocket AMI types (EKS adds the AL2/AL2023 bootstrap shim itself). NEVER set in caller TOML: `settings.kubernetes.cluster-name`, `api-server`, `cluster-certificate`, `cluster-dns-ip` (pluto/schnauzer auto-derive at first boot — overriding breaks bootstrap); `settings.kubernetes.kube-reserved` (schnauzer auto-calcs from max-pods)."
  type = map(object({
    create                     = optional(bool, true)
    name                       = optional(string)
    instance_types             = optional(list(string), ["t3.medium"])
    min_size                   = optional(number, 1)
    max_size                   = optional(number, 10)
    desired_size               = optional(number, 1)
    capacity_type              = optional(string, "ON_DEMAND")
    ami_type                   = optional(string, "BOTTLEROCKET_x86_64")
    ami_release_version        = optional(string)
    labels                     = optional(map(string), {})
    taints                     = optional(map(object({ key = string, value = optional(string), effect = string })), {})
    tags                       = optional(map(string), {})
    iam_role_use_name_prefix   = optional(bool, false)
    enable_node_repair         = optional(bool)
    max_unavailable_percentage = optional(number, 33)
    enable_monitoring          = optional(bool, true)
    bottlerocket_user_data     = optional(string)
    # block_device_mappings: map key = mapping name (free-form). device_name
    # defaults to /dev/xvda (BOTTLEROCKET_x86_64 / AL2 root); Bottlerocket data
    # volume uses a second entry with /dev/xvdb. iops/throughput only apply to
    # volume_type io1/io2/gp3. kms_key_id = null → local.ebs_kms_key_arn.
    block_device_mappings = optional(map(object({
      device_name           = optional(string, "/dev/xvda")
      volume_size           = optional(number, 20)
      volume_type           = optional(string, "gp3")
      iops                  = optional(number)
      throughput            = optional(number)
      encrypted             = optional(bool, true)
      delete_on_termination = optional(bool, true)
      kms_key_id            = optional(string)
    })), {})
  }))
  default = {
    infra = {
      instance_types = ["t3.medium"]
      ami_type       = "BOTTLEROCKET_x86_64"
      min_size       = 2
      max_size       = 10
      desired_size   = 1
      labels         = { role = "infra" }
      taints = {
        infra = { key = "role", value = "infra", effect = "NO_SCHEDULE" }
      }
      block_device_mappings = {
        root = {
          device_name = "/dev/xvda"
          volume_size = 4
          volume_type = "gp3"
        }
        data = {
          device_name = "/dev/xvdb"
          volume_size = 50
          volume_type = "gp3"
        }
      }
    }
  }

  validation {
    condition = alltrue([
      for k, v in var.eks_managed_node_groups :
      v.bottlerocket_user_data == null || length(trimspace(v.bottlerocket_user_data)) > 0
    ])
    error_message = "bottlerocket_user_data, when set, must be non-empty TOML (whitespace-only values are rejected)."
  }

  validation {
    condition = alltrue([
      for k, v in var.eks_managed_node_groups :
      v.bottlerocket_user_data == null || startswith(v.ami_type, "BOTTLEROCKET_")
    ])
    error_message = "bottlerocket_user_data is only valid when ami_type startswith \"BOTTLEROCKET_\" (AL2/AL2023/Windows AMIs use the EKS bootstrap shim and ignore custom user_data here)."
  }
}

variable "eks_managed_node_group_defaults" {
  description = "Defaults applied to every managed node group. Per-group overrides win. enable_monitoring and use_latest_ami_release_version are pinned here to preserve v20 behavior after the v21 default flips (true->false and false->true respectively)."
  type        = any
  default = {
    attach_cluster_primary_security_group = false
    enable_monitoring                     = true
    use_latest_ami_release_version        = false
  }
}

variable "cluster_addons" {
  description = "Map of EKS add-ons to enable. 3-phase bootstrap controlled by per-addon `depends_on_node_group` flag: (1) PRE-NODE addons (flag false/absent) install before any node group → vpc-cni MUST be here so the aws-node DaemonSet + custom-networking env vars exist before kubelet registers; (2) node groups launch with depends_on=[aws_eks_addon.this, kubectl_manifest.eniconfig]; (3) POST-NODE addons (flag true) install after nodes — kube-proxy / eks-pod-identity-agent / coredns + ebs_csi / efs_csi. resolve_conflicts_on_create=OVERWRITE and most_recent=false are pinned per-addon. Default configuration_values pin add-ons onto the infra node group: CoreDNS (Deployment) gets nodeSelector role=infra plus a matching toleration; vpc-cni / eks-pod-identity-agent (DaemonSets) get tolerations=[{operator: Exists}] so they land on any tainted node. kube-proxy ships with `tolerations: [{operator: Exists}]` natively and its addon schema does NOT accept a `tolerations` key — leave configuration_values unset. Supplying configuration_values per add-on overrides the default for that add-on entirely."
  type        = any
  default = {
    coredns = {
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      most_recent                 = false
      depends_on_node_group       = true
      configuration_values        = "{\"nodeSelector\":{\"role\":\"infra\"},\"tolerations\":[{\"key\":\"role\",\"operator\":\"Equal\",\"value\":\"infra\",\"effect\":\"NoSchedule\"}]}"
    }
    kube-proxy = {
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      most_recent                 = false
      depends_on_node_group       = true
      # kube-proxy addon schema does NOT accept `tolerations` — the DaemonSet
      # ships with `tolerations: [{operator: Exists}]` natively and runs on
      # every node by design. Setting tolerations via configuration_values
      # fails with InvalidParameterException (JSON schema validation).
    }
    vpc-cni = {
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      most_recent                 = false
      # vpc-cni MUST install BEFORE nodes register (carries custom-networking
      # env vars + provisions aws-node DaemonSet). depends_on_node_group = false
      # (default) — installs in pre-node phase.
      configuration_values = "{\"env\":{},\"tolerations\":[{\"operator\":\"Exists\"}]}"
    }
    eks-pod-identity-agent = {
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      most_recent                 = false
      depends_on_node_group       = true
      configuration_values        = "{\"tolerations\":[{\"operator\":\"Exists\"}]}"
    }
  }
}

variable "access_entries" {
  description = "Full map of EKS access entries to create. Caller supplies the complete map — module ships NO built-in entries. Key = entry name. Each value: { principal_arn, policy_associations = { <assoc_key> = { policy_arn, access_scope = { type, namespaces? } } } }."
  type        = any
  default     = {}
}

variable "enable_vpc_cni_custom_networking" {
  description = "Enable VPC CNI custom networking ('2nd networking'). Module injects AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true and ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone into the vpc-cni addon configuration_values AND renders one ENIConfig CR per AZ (via kubectl provider) keyed on var.pod_subnet_ids_by_az. Caller still must provision the secondary VPC CIDR + per-AZ pod subnets (see networking module). Assumes cluster API server is reachable from the Terraform runner. See https://docs.aws.amazon.com/eks/latest/userguide/cni-custom-network.html"
  type        = bool
  default     = false
}

variable "pod_subnet_ids_by_az" {
  description = "Map of AZ name -> pod subnet ID for VPC CNI custom networking. Required when enable_vpc_cni_custom_networking = true. One entry per AZ; the AZ name is used verbatim as the ENIConfig CR name (matches ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone)."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.pod_subnet_ids_by_az : can(regex("^subnet-", v))])
    error_message = "Every value of pod_subnet_ids_by_az must be a subnet ID (subnet-...)."
  }
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "endpoint_public_access" {
  description = "Whether the EKS API server endpoint is reachable from the public internet (restricted further by var.allowed_cidrs)."
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  description = "Whether the EKS API server endpoint is reachable from inside the VPC."
  type        = bool
  default     = true
}

variable "enabled_log_types" {
  description = "EKS control-plane log types to ship to CloudWatch Logs."
  type        = list(string)
  default = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]
}

variable "enable_irsa" {
  description = "Whether to create the OIDC provider required by IAM Roles for Service Accounts."
  type        = bool
  default     = true
}

variable "authentication_mode" {
  description = "EKS authentication mode. API is the recommended approach (access entries only, no aws-auth ConfigMap). Transitions are ONE-WAY: CONFIG_MAP -> API_AND_CONFIG_MAP -> API. You cannot downgrade. Clusters migrating from API_AND_CONFIG_MAP must override explicitly; new clusters should use the default API."
  type        = string
  default     = "API"
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Whether the IAM principal that runs `terraform apply` is auto-granted cluster-admin via an implicit access entry. Disabled so the explicit operator access entry is the single source of truth."
  type        = bool
  default     = false
}

variable "partition_placeholder" {
  description = "Literal placeholder token in cluster access policy ARN templates substituted with data.aws_partition.current.partition at apply time."
  type        = string
  default     = "__AWS_PARTITION__"
}

variable "node_group_name_separator" {
  description = "Separator placed between var.name and the node-group map key when synthesizing the upstream `name` argument."
  type        = string
  default     = "-"
}

variable "cluster_autoscaler_enabled_tag_key" {
  description = "Node group tag key signalling that Cluster Autoscaler should consider this ASG."
  type        = string
  default     = "k8s.io/cluster-autoscaler/enabled"
}

variable "cluster_autoscaler_enabled_tag_value" {
  description = "Node group tag value for the Cluster Autoscaler enabled tag."
  type        = string
  default     = "true"
}

variable "cluster_autoscaler_owned_tag_key_prefix" {
  description = "Prefix for the per-cluster Cluster Autoscaler ownership tag. The full EKS cluster name (var.name + var.cluster_name_suffix) is appended to form the full key (k8s.io/cluster-autoscaler/<cluster_name>)."
  type        = string
  default     = "k8s.io/cluster-autoscaler/"
}

variable "cluster_autoscaler_owned_tag_value" {
  description = "Tag value applied to k8s.io/cluster-autoscaler/<cluster_name> on managed node group ASGs."
  type        = string
  default     = "owned"
}

variable "karpenter_discovery_tag_key" {
  description = "Tag key consumed by Karpenter EC2NodeClass.securityGroupSelectorTerms / subnetSelectorTerms (and applied to karpenter sub-module resources). Tag value is the full EKS cluster name (var.name + var.cluster_name_suffix)."
  type        = string
  default     = "karpenter.sh/discovery"
}

variable "karpenter_create_pod_identity_association" {
  description = "Whether the upstream karpenter sub-module should create an EKS Pod Identity association for the controller IAM role."
  type        = bool
  default     = true
}

variable "karpenter_create_instance_profile" {
  description = "Whether the upstream karpenter sub-module should create the EC2 instance profile attached to Karpenter-provisioned nodes."
  type        = bool
  default     = true
}

variable "karpenter_iam_role_name_suffix" {
  description = "Suffix appended to var.name to form the karpenter controller IAM role name."
  type        = string
  default     = "-karpenter-controller-role"
}

variable "karpenter_iam_policy_name_suffix" {
  description = "Suffix appended to var.name to form the karpenter controller IAM policy name."
  type        = string
  default     = "-karpenter-controller-policy"
}

variable "karpenter_iam_role_use_name_prefix" {
  description = "Whether the upstream karpenter sub-module treats iam_role_name as a name_prefix instead of a fixed name."
  type        = bool
  default     = false
}

variable "karpenter_iam_policy_use_name_prefix" {
  description = "Whether the upstream karpenter sub-module treats iam_policy_name as a name_prefix instead of a fixed name."
  type        = bool
  default     = false
}

variable "karpenter_node_iam_role_name_suffix" {
  description = "Suffix appended to var.name to form the karpenter node IAM role name."
  type        = string
  default     = "-karpenter-node-role"
}

variable "karpenter_node_iam_role_use_name_prefix" {
  description = "Whether the upstream karpenter sub-module treats node_iam_role_name as a name_prefix instead of a fixed name."
  type        = bool
  default     = false
}

variable "karpenter_queue_name_suffix" {
  description = "Suffix appended to var.name to form the karpenter SQS queue name (receives EC2 spot interruption / health events)."
  type        = string
  default     = "-karpenter-queue"
}

variable "karpenter_node_additional_policies" {
  description = "Additional managed-policy ARNs (keyed by short name) attached to the karpenter node IAM role. The literal var.partition_placeholder is substituted with data.aws_partition.current.partition at apply time. Default: SSM Session Manager access."
  type        = map(string)
  default = {
    AmazonSSMManagedInstanceCore = "arn:__AWS_PARTITION__:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

variable "pod_identity_associations" {
  description = "Map of EKS Pod Identity associations to create against this cluster. Keyed by short name (typically the IAM role's map key in the iam module). Each entry binds a Kubernetes ServiceAccount (namespace + service_account) to an IAM role ARN. Feed module.iam.pod_identity_role_bindings straight in."
  type = map(object({
    namespace            = string
    service_account      = string
    role_arn             = string
    disable_session_tags = optional(bool, false)
  }))
  default = {}
}

variable "kms_deletion_window_days" {
  description = "Number of days before KMS key deletion after removal. Range 7-30."
  type        = number
  default     = 30
}

variable "kms_enable_key_rotation" {
  description = "Whether to enable automatic annual key rotation for KMS keys."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days for EKS control-plane logs."
  type        = number
  default     = 7
}

variable "service_ipv4_cidr" {
  description = "IPv4 CIDR block to assign to Kubernetes service addresses. Leave null to let EKS choose (default 172.20.0.0/16)."
  type        = string
  default     = null
}

variable "fargate_profiles" {
  description = "Map of Fargate profile definitions. Each entry creates an aws_eks_fargate_profile. Default empty — no Fargate by default. Map key = profile name. Each value has a 'selectors' list of objects with 'namespace' (required) and 'labels' (optional map)."
  type = map(object({
    selectors = list(object({
      namespace = string
      labels    = optional(map(string), {})
    }))
  }))
  default = {}
}

variable "enable_ebs_csi_addon" {
  description = "Whether to create the EBS CSI driver addon with a module-managed IAM role via Pod Identity."
  type        = bool
  default     = true
}

variable "enable_efs_csi_addon" {
  description = "Whether to create the EFS CSI driver addon with a module-managed IAM role via Pod Identity."
  type        = bool
  default     = true
}

variable "ebs_csi_addon_version" {
  description = "Version of the EBS CSI driver addon. Null = use latest compatible version."
  type        = string
  default     = null
}

variable "efs_csi_addon_version" {
  description = "Version of the EFS CSI driver addon. Null = use latest compatible version."
  type        = string
  default     = null
}

variable "ebs_csi_addon_configuration_values" {
  description = "Raw JSON string passed to the aws-ebs-csi-driver addon `configuration_values`. Default (a) enables `defaultStorageClass` which provisions the `ebs-csi-default-sc` gp3 default StorageClass (WaitForFirstConsumer) that workloads like Jenkins PVCs reference, (b) pins the EBS CSI controller Deployment onto the infra node group (nodeSelector role=infra + matching toleration), and (c) tolerates any taint on the ebs-csi-node DaemonSet so it lands on every node. REPLACE semantics: supplying a value fully replaces the default. Set to null to leave addon defaults untouched (no default StorageClass)."
  type        = string
  default     = "{\"defaultStorageClass\":{\"enabled\":true},\"controller\":{\"nodeSelector\":{\"role\":\"infra\"},\"tolerations\":[{\"key\":\"role\",\"operator\":\"Equal\",\"value\":\"infra\",\"effect\":\"NoSchedule\"}]},\"node\":{\"tolerations\":[{\"operator\":\"Exists\"}]}}"
}

variable "efs_csi_addon_configuration_values" {
  description = "Raw JSON string passed to the aws-efs-csi-driver addon `configuration_values`. Default pins the EFS CSI controller Deployment onto the infra node group (nodeSelector role=infra + matching toleration) and tolerates any taint on the efs-csi-node DaemonSet so it lands on every node. REPLACE semantics: supplying a value fully replaces the default. Set to null to leave addon defaults untouched."
  type        = string
  default     = "{\"controller\":{\"nodeSelector\":{\"role\":\"infra\"},\"tolerations\":[{\"key\":\"role\",\"operator\":\"Equal\",\"value\":\"infra\",\"effect\":\"NoSchedule\"}]},\"node\":{\"tolerations\":[{\"operator\":\"Exists\"}]}}"
}

variable "karpenter_namespace" {
  description = "Namespace where Karpenter controller runs."
  type        = string
  default     = "kube-system"
}

variable "karpenter_service_account" {
  description = "Service account name for Karpenter controller."
  type        = string
  default     = "karpenter"
}

variable "cluster_upgrade_support_type" {
  description = "EKS upgrade support type. STANDARD = auto-upgrade at end of standard support window (14 months, no extra fee). EXTENDED = opt-in to 12-month extended support (additional cost). Recommended: STANDARD."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.cluster_upgrade_support_type)
    error_message = "cluster_upgrade_support_type must be STANDARD or EXTENDED."
  }
}

variable "enable_zonal_shift" {
  description = "Whether to enable ARC zonal shift on the EKS cluster. Allows shifting traffic away from an impaired AZ without DNS changes. Requires ARC zonal shift to be configured in the account."
  type        = bool
  default     = false
}

variable "enable_deletion_protection" {
  description = "Whether to enable deletion protection on the EKS cluster. When true, the cluster cannot be deleted via Terraform destroy or the AWS console until protection is explicitly disabled. Recommended true for production."
  type        = bool
  default     = false
}

variable "enable_auto_mode" {
  description = "Whether to enable EKS Auto Mode on the cluster. Auto Mode delegates node provisioning, scaling, and patching to AWS. Requires additional cluster IAM policies (created conditionally). Default false — opt-in only."
  type        = bool
  default     = false
}

variable "auto_mode_node_pools" {
  description = "Node pool types when EKS Auto Mode is enabled. Valid values: general-purpose, system. Only relevant when enable_auto_mode = true."
  type        = list(string)
  default     = ["general-purpose", "system"]
}

variable "node_repair_enabled" {
  description = "Whether to enable automatic node repair on managed node groups. When enabled, EKS detects and replaces unhealthy nodes automatically. Default false — opt-in. Per-group override via enable_node_repair in eks_managed_node_groups."
  type        = bool
  default     = false
}

variable "existing_cluster_kms_key_arn" {
  description = "ARN of an existing customer-managed KMS key to use for EKS cluster envelope (secrets) encryption. When null (default), the module creates and owns aws_kms_key.cluster + alias. When set, the module skips key creation and consumes the supplied ARN — the alias is NOT created either."
  type        = string
  default     = null
}

variable "existing_ebs_kms_key_arn" {
  description = "ARN of an existing customer-managed KMS key to use for EBS volume encryption on managed/Karpenter nodes. When null (default), the module creates and owns aws_kms_key.ebs + alias + key policy. The module-managed policy grants: (a) node + karpenter_node IAM roles Encrypt/Decrypt/ReEncrypt*/GenerateDataKey*/DescribeKey, (b) the AWSServiceRoleForAutoScaling SLR (NOT the autoscaling.amazonaws.com Service principal — that form is a silent no-op for SLR services) the same 5 actions plus CreateGrant conditioned on kms:GrantIsForAWSResource=true. When set, the caller MUST replicate all three grants on the BYO key (see node_iam_role_arn / karpenter_node_iam_role_arn outputs). Reference: https://docs.aws.amazon.com/autoscaling/ec2/userguide/key-policy-requirements-EBS-encryption.html"
  type        = string
  default     = null
}

variable "node_security_group_additional_rules" {
  description = "Override node security group rules. REPLACE semantics: when ingress or egress is non-null, the caller-supplied map fully replaces the canonical default set (cluster→node 443/10250/4443/6443/8443/9443; self CoreDNS 53 tcp+udp + ephemeral 1025-65535; egress 0.0.0.0/0). Set ingress=null and/or egress=null to keep defaults. Each rule supports: description, ip_protocol, from_port, to_port, cidr_ipv4 (or source='cluster'|'self' for SG-referenced rules; egress also supports referenced_security_group_id)."
  type = object({
    ingress = optional(map(any))
    egress  = optional(map(any))
  })
  default = {}
}
