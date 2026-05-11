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

  # CSI controller Pod Identity role ARNs sourced from module.iam outputs.
  # Terraform variable defaults cannot reference module outputs, so the CSI
  # addon entries in var.cluster_addons carry an empty role_arn placeholder
  # and we patch them here at the module.eks call site.
  csi_role_arns = {
    aws-ebs-csi-driver = module.iam.ebs_csi_controller_role_arn
    aws-efs-csi-driver = module.iam.efs_csi_controller_role_arn
  }

  cluster_addons_resolved = {
    for k, v in var.cluster_addons : k => (
      contains(keys(local.csi_role_arns), k)
      ? merge(v, {
        pod_identity_association = [
          for assoc in v.pod_identity_association : merge(assoc, {
            role_arn = local.csi_role_arns[k]
          })
        ]
      })
      : v
    )
  }

  # POC: jenkins-agent is granted cluster-admin via EKS access entry so the
  # deploy pipeline can create namespaces and reconcile CRDs (KEDA
  # ScaledObject, external-secrets ExternalSecret) without bespoke RBAC.
  # Production must replace this with least-privilege per-namespace RBAC.
  eks_access_entries_effective = merge(
    {
      jenkins-agent = {
        principal_arn = module.iam.pod_identity_role_arns["jenkins-agent"]
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
    var.eks_access_entries,
  )
}
