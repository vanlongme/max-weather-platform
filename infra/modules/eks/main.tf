module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id                   = var.vpc_id
  subnet_ids               = var.subnet_ids
  control_plane_subnet_ids = var.subnet_ids

  cluster_endpoint_public_access       = true
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = var.allowed_cidrs

  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  enable_irsa = true

  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = false

  access_entries = merge(
    {
      operator = {
        principal_arn = var.operator_principal_arn
        policy_associations = {
          admin = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = {
              type = "cluster"
            }
          }
        }
      }
    },
    var.jenkins_role_arn == "" ? {} : {
      jenkins = {
        principal_arn = var.jenkins_role_arn
        policy_associations = {
          edit = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
            access_scope = {
              type       = "namespace"
              namespaces = ["weather-staging", "weather-prod"]
            }
          }
        }
      }
    },
    var.access_entries,
  )

  cluster_addons = var.cluster_addons

  eks_managed_node_group_defaults = var.eks_managed_node_group_defaults

  eks_managed_node_groups = {
    for k, v in var.eks_managed_node_groups : k => merge(
      v,
      {
        name = coalesce(v.name, "${var.cluster_name}-${k}")
        tags = merge(var.tags, v.tags, {
          "k8s.io/cluster-autoscaler/enabled"             = "true"
          "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
        })
      }
    )
  }

  node_security_group_tags = merge(var.tags, {
    "karpenter.sh/discovery" = var.cluster_name
  })

  tags = var.tags
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.24"

  cluster_name = module.eks.cluster_name

  enable_v1_permissions = true

  enable_irsa             = true
  irsa_oidc_provider_arn  = module.eks.oidc_provider_arn
  create_instance_profile = true

  iam_role_name              = "${var.cluster_name}-karpenter-controller"
  iam_role_use_name_prefix   = false
  iam_policy_name            = "${var.cluster_name}-karpenter-controller"
  iam_policy_use_name_prefix = false

  node_iam_role_name              = "${var.cluster_name}-karpenter-node"
  node_iam_role_use_name_prefix   = false
  create_pod_identity_association = false

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  queue_name = "${var.cluster_name}-karpenter"

  tags = merge(var.tags, {
    "karpenter.sh/discovery" = var.cluster_name
  })
}
