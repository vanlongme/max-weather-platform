resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = var.chart_version
  namespace  = "kube-system"

  values = [
    yamlencode({
      autoDiscovery = {
        clusterName = var.cluster_name
      }
      awsRegion = var.aws_region
      rbac = {
        serviceAccount = {
          name = "cluster-autoscaler"
          annotations = {
            "eks.amazonaws.com/role-arn" = var.irsa_role_arn
          }
        }
      }
      extraArgs = {
        scale-down-delay-after-add  = "5m"
        scale-down-unneeded-time    = "5m"
        balance-similar-node-groups = "true"
        skip-nodes-with-system-pods = "false"
      }
    })
  ]
}
