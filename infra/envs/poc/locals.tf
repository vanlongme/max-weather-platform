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

  # POC: jenkins-agent is granted cluster-admin via EKS access entry so the
  # deploy pipeline can reconcile workloads + CRDs (KEDA ScaledObject,
  # external-secrets ExternalSecret) and create namespaces on demand.
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
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
      # type=EC2_LINUX is REQUIRED for the Karpenter node IAM role under
      # authentication_mode = "API": kubelet on Karpenter-provisioned Bottlerocket
      # workers IAM-auths via this entry (registers with system:nodes group +
      # node-name SAN). Standard policy_associations are not used — EKS auto-binds
      # the EC2_LINUX entry to the built-in node policy. Without it kubelet logs
      # "Unauthorized" and nodes never register.
      karpenter-node = {
        principal_arn       = module.eks.karpenter_node_iam_role_arn
        type                = "EC2_LINUX"
        policy_associations = {}
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
