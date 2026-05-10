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

  access_entries = {
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
  }

  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
  }

  eks_managed_node_group_defaults = {
    ami_type                              = "AL2023_x86_64_STANDARD"
    capacity_type                         = "ON_DEMAND"
    disk_size                             = var.node_disk_size
    attach_cluster_primary_security_group = false
  }

  eks_managed_node_groups = {
    general = {
      name           = "${var.cluster_name}-general"
      instance_types = var.node_instance_types
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size

      labels = {
        role = "general"
      }

      tags = merge(var.tags, {
        "k8s.io/cluster-autoscaler/enabled"             = "true"
        "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      })
    }
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
