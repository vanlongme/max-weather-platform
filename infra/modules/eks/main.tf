# main.tf - all aws_eks_* resources for this module.
# Per repo convention, main.tf holds every resource of the module's primary
# AWS service family. Supporting resources (IAM, KMS, security groups,
# launch templates, OIDC provider, CloudWatch log groups, SQS, EventBridge)
# live in component-named files.

# ──────────────────────────────────────────
# Cluster
# ──────────────────────────────────────────

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  # Always false: module owns every addon as a managed aws_eks_addon resource
  # (cluster_addons + ebs_csi + efs_csi). AWS legacy self-managed addon bootstrap
  # at cluster creation is fully suppressed.
  bootstrap_self_managed_addons = false
  deletion_protection           = var.enable_deletion_protection

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = var.endpoint_public_access
    endpoint_private_access = var.endpoint_private_access
    public_access_cidrs     = var.endpoint_public_access ? var.allowed_cidrs : null
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = local.cluster_kms_key_arn
    }
  }

  enabled_cluster_log_types = var.enabled_log_types

  access_config {
    authentication_mode                         = var.authentication_mode
    bootstrap_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
  }

  kubernetes_network_config {
    service_ipv4_cidr = var.service_ipv4_cidr

    dynamic "elastic_load_balancing" {
      for_each = var.enable_auto_mode ? [1] : []
      content {
        enabled = true
      }
    }
  }

  dynamic "compute_config" {
    for_each = var.enable_auto_mode ? [1] : []
    content {
      enabled       = true
      node_pools    = var.auto_mode_node_pools
      node_role_arn = aws_iam_role.node.arn
    }
  }

  dynamic "storage_config" {
    for_each = var.enable_auto_mode ? [1] : []
    content {
      block_storage {
        enabled = true
      }
    }
  }

  upgrade_policy {
    support_type = var.cluster_upgrade_support_type
  }

  zonal_shift_config {
    enabled = var.enable_zonal_shift
  }

  tags = merge(var.tags, {
    Name = local.cluster_name
  })

  depends_on = [
    aws_cloudwatch_log_group.cluster,
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_resource_controller,
  ]

  lifecycle {
    # Fail-fast at plan time when custom networking is enabled without per-AZ
    # pod subnets — silent collapse of kubectl_manifest.eniconfig for_each
    # would otherwise leave the cluster with zero ENIConfig CRs and break
    # node bootstrap. Caller must supply pod_subnet_ids_by_az (typically
    # module.networking.pod_subnet_ids_by_az + secondary_vpc_cidrs/pod_subnet_cidrs).
    precondition {
      condition     = !var.enable_vpc_cni_custom_networking || length(var.pod_subnet_ids_by_az) > 0
      error_message = "enable_vpc_cni_custom_networking=true requires non-empty pod_subnet_ids_by_az. Provision a secondary VPC CIDR + per-AZ pod subnets (see modules/networking: secondary_vpc_cidrs + pod_subnet_cidrs) and wire its pod_subnet_ids_by_az output into this module."
    }
  }
}

# ──────────────────────────────────────────
# Access entries + policy associations
# ──────────────────────────────────────────

resource "aws_eks_access_entry" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn

  tags = var.tags
}

resource "aws_eks_access_policy_association" "this" {
  for_each = {
    for pair in flatten([
      for entry_key, entry in var.access_entries : [
        for assoc_key, assoc in entry.policy_associations : {
          key          = "${entry_key}:${assoc_key}"
          entry_key    = entry_key
          policy_arn   = assoc.policy_arn
          access_scope = assoc.access_scope
        }
      ]
    ]) : pair.key => pair
  }

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.access_entries[each.value.entry_key].principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.access_scope.type
    namespaces = try(each.value.access_scope.namespaces, null)
  }

  depends_on = [aws_eks_access_entry.this]
}

# ──────────────────────────────────────────
# Addons
# ──────────────────────────────────────────

resource "aws_eks_addon" "this" {
  for_each = {
    for k, v in local.cluster_addons_effective : k => v
    if !try(v.depends_on_node_group, false)
  }

  cluster_name = aws_eks_cluster.this.name
  addon_name   = each.key

  addon_version               = try(each.value.addon_version, null)
  resolve_conflicts_on_create = try(each.value.resolve_conflicts_on_create, "OVERWRITE")
  resolve_conflicts_on_update = try(each.value.resolve_conflicts_on_update, "OVERWRITE")
  configuration_values        = try(each.value.configuration_values, null)

  tags = var.tags
}

resource "aws_eks_addon" "post_node" {
  for_each = {
    for k, v in local.cluster_addons_effective : k => v
    if try(v.depends_on_node_group, false)
  }

  cluster_name = aws_eks_cluster.this.name
  addon_name   = each.key

  addon_version               = try(each.value.addon_version, null)
  resolve_conflicts_on_create = try(each.value.resolve_conflicts_on_create, "OVERWRITE")
  resolve_conflicts_on_update = try(each.value.resolve_conflicts_on_update, "OVERWRITE")
  configuration_values        = try(each.value.configuration_values, null)

  tags = var.tags

  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "ebs_csi" {
  count = var.enable_ebs_csi_addon ? 1 : 0

  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "aws-ebs-csi-driver"
  addon_version = var.ebs_csi_addon_version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = var.ebs_csi_addon_configuration_values

  pod_identity_association {
    role_arn        = aws_iam_role.ebs_csi_controller[0].arn
    service_account = "ebs-csi-controller-sa"
  }

  tags = var.tags

  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "efs_csi" {
  count = var.enable_efs_csi_addon ? 1 : 0

  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "aws-efs-csi-driver"
  addon_version = var.efs_csi_addon_version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = var.efs_csi_addon_configuration_values

  pod_identity_association {
    role_arn        = aws_iam_role.efs_csi_controller[0].arn
    service_account = "efs-csi-controller-sa"
  }

  tags = var.tags

  depends_on = [aws_eks_node_group.this]
}

# ──────────────────────────────────────────
# Fargate profile
# ──────────────────────────────────────────

resource "aws_eks_fargate_profile" "this" {
  for_each = var.fargate_profiles

  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = each.key
  pod_execution_role_arn = aws_iam_role.fargate.arn
  subnet_ids             = var.subnet_ids

  dynamic "selector" {
    for_each = each.value.selectors
    content {
      namespace = selector.value.namespace
      labels    = try(selector.value.labels, {})
    }
  }

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-${each.key}"
  })
}

# ──────────────────────────────────────────
# Managed node group
# Each group binds to a module-managed aws_launch_template (see
# launch_template.tf) so callers can configure volume_type / iops /
# throughput / device_name beyond what the native disk_size arg supports.
# ──────────────────────────────────────────

resource "aws_eks_node_group" "this" {
  for_each = var.eks_managed_node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = coalesce(each.value.name, "${var.name}${var.node_group_name_separator}${each.key}")
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  instance_types  = each.value.instance_types
  ami_type        = each.value.ami_type
  capacity_type   = each.value.capacity_type
  release_version = each.value.ami_release_version

  launch_template {
    id      = aws_launch_template.node[each.key].id
    version = aws_launch_template.node[each.key].latest_version
  }

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  node_repair_config {
    enabled = try(each.value.enable_node_repair, var.node_repair_enabled)
  }

  update_config {
    max_unavailable_percentage = try(each.value.max_unavailable_percentage, 33)
  }

  labels = each.value.labels

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = try(taint.value.value, null)
      effect = taint.value.effect
    }
  }

  tags = merge(var.tags, each.value.tags, {
    (var.cluster_autoscaler_enabled_tag_key)                              = var.cluster_autoscaler_enabled_tag_value
    "${var.cluster_autoscaler_owned_tag_key_prefix}${local.cluster_name}" = var.cluster_autoscaler_owned_tag_value
    (var.karpenter_discovery_tag_key)                                     = local.cluster_name
  })

  # before_compute ordering: VPC CNI addon + (when custom networking enabled)
  # ENIConfig CRs must exist before any node registers. kubectl_manifest.eniconfig
  # is gated on var.enable_vpc_cni_custom_networking — when false, the for_each
  # collapses to {} and the dep is a no-op.
  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_readonly,
    aws_eks_addon.this,
    kubectl_manifest.eniconfig,
  ]
}

# ──────────────────────────────────────────
# Pod Identity associations
# ──────────────────────────────────────────

resource "aws_eks_pod_identity_association" "this" {
  for_each = var.pod_identity_associations

  cluster_name         = aws_eks_cluster.this.name
  namespace            = each.value.namespace
  service_account      = each.value.service_account
  role_arn             = each.value.role_arn
  disable_session_tags = try(each.value.disable_session_tags, false)
  tags                 = var.tags
}

resource "aws_eks_pod_identity_association" "karpenter" {
  count = var.karpenter_create_pod_identity_association ? 1 : 0

  cluster_name    = aws_eks_cluster.this.name
  namespace       = var.karpenter_namespace
  service_account = var.karpenter_service_account
  role_arn        = aws_iam_role.karpenter_controller.arn

  tags = var.tags
}
