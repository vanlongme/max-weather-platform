locals {
  # Environment is derived from this composition's directory name.
  # e.g. infra/envs/poc -> "poc", infra/envs/staging -> "staging".
  environment = basename(path.cwd)

  # master_prefix is the canonical prefix applied to every resource name
  # produced by this composition. Format: "<environment>-<project>".
  # e.g. "poc-max-weather".
  master_prefix = "${local.environment}-${var.project}"

  common_tags = {
    Project     = var.project
    Environment = local.environment
    ManagedBy   = "terraform"
  }

  # POC: jenkins-agent is granted namespaced admin via EKS access entry so the
  # deploy pipeline can reconcile workloads + CRDs (KEDA ScaledObject,
  # external-secrets ExternalSecret) across the four operational namespaces.
  # Production must replace this with least-privilege RBAC.
  eks_access_entries_effective = merge(
    {
      operator = {
        principal_arn = data.aws_caller_identity.current.arn
        policy_associations = {
          admin = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
      jenkins-agent = {
        principal_arn = module.iam.pod_identity_role_arns["jenkins-agent"]
        policy_associations = {
          admin = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = {
              type       = "namespace"
              namespaces = ["default", "weather-staging", "weather-prod", "jenkins"]
            }
          }
        }
      }
    },
    var.eks_access_entries,
  )

  # Single infra MNG in PUBLIC subnets — Jenkins + platform controllers; workload via Karpenter (private)
  eks_managed_node_groups_with_subnets = {
    for k, v in var.eks_managed_node_groups : k => merge(v, {
      subnet_ids = module.networking.public_subnet_ids
    })
  }
}
