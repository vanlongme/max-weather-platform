module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.20"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  vpc_id                   = var.vpc_id
  subnet_ids               = var.subnet_ids
  control_plane_subnet_ids = var.subnet_ids

  endpoint_public_access       = var.endpoint_public_access
  endpoint_private_access      = var.endpoint_private_access
  endpoint_public_access_cidrs = var.allowed_cidrs

  enabled_log_types = var.enabled_log_types

  enable_irsa = var.enable_irsa

  authentication_mode                      = var.authentication_mode
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  access_entries = merge(
    {
      (var.operator_access_entry_key) = {
        principal_arn = var.operator_principal_arn
        policy_associations = {
          (var.operator_policy_association_key) = {
            policy_arn = replace(var.operator_cluster_access_policy_arn_template, var.partition_placeholder, data.aws_partition.current.partition)
            access_scope = {
              type = var.operator_access_scope_type
            }
          }
        }
      }
    },
    var.jenkins_role_arn == "" ? {} : {
      (var.jenkins_access_entry_key) = {
        principal_arn = var.jenkins_role_arn
        policy_associations = {
          (var.jenkins_policy_association_key) = {
            policy_arn = replace(var.jenkins_cluster_access_policy_arn_template, var.partition_placeholder, data.aws_partition.current.partition)
            access_scope = {
              type       = var.jenkins_access_scope_type
              namespaces = var.jenkins_access_namespaces
            }
          }
        }
      }
    },
    var.access_entries,
  )

  addons = var.cluster_addons

  eks_managed_node_groups = {
    for k, v in var.eks_managed_node_groups : k => merge(
      var.eks_managed_node_group_defaults,
      v,
      {
        name = coalesce(v.name, "${var.cluster_name}${var.node_group_name_separator}${k}")
        tags = merge(var.tags, v.tags, {
          (var.cluster_autoscaler_enabled_tag_key)                            = var.cluster_autoscaler_enabled_tag_value
          "${var.cluster_autoscaler_owned_tag_key_prefix}${var.cluster_name}" = var.cluster_autoscaler_owned_tag_value
        })
      }
    )
  }

  node_security_group_tags = merge(var.tags, {
    (var.karpenter_discovery_tag_key) = var.cluster_name
  })

  tags = var.tags
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.20"

  cluster_name = module.eks.cluster_name

  create_pod_identity_association = var.karpenter_create_pod_identity_association
  create_instance_profile         = var.karpenter_create_instance_profile

  iam_role_name              = "${var.cluster_name}${var.karpenter_iam_role_name_suffix}"
  iam_role_use_name_prefix   = var.karpenter_iam_role_use_name_prefix
  iam_policy_name            = "${var.cluster_name}${var.karpenter_iam_role_name_suffix}"
  iam_policy_use_name_prefix = var.karpenter_iam_policy_use_name_prefix

  node_iam_role_name            = "${var.cluster_name}${var.karpenter_node_iam_role_name_suffix}"
  node_iam_role_use_name_prefix = var.karpenter_node_iam_role_use_name_prefix

  node_iam_role_additional_policies = {
    for k, v in var.karpenter_node_additional_policies : k => replace(v, var.partition_placeholder, data.aws_partition.current.partition)
  }

  queue_name = "${var.cluster_name}${var.karpenter_queue_name_suffix}"

  tags = merge(var.tags, {
    (var.karpenter_discovery_tag_key) = var.cluster_name
  })
}
