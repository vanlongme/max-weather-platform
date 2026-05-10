resource "helm_release" "fluent_bit" {
  name             = "aws-for-fluent-bit"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-for-fluent-bit"
  version          = var.chart_version
  namespace        = "amazon-cloudwatch"
  create_namespace = true

  values = [
    yamlencode({
      cloudWatchLogs = {
        enabled         = true
        region          = var.aws_region
        logGroupName    = var.log_group_name
        logStreamPrefix = "fluent-bit-"
        autoCreateGroup = false
      }
      kinesis = {
        enabled = false
      }
      firehose = {
        enabled = false
      }
      elasticsearch = {
        enabled = false
      }
      serviceAccount = {
        create = true
        name   = "fluent-bit"
        annotations = {
          "eks.amazonaws.com/role-arn" = var.irsa_role_arn
        }
      }
      tolerations = [
        {
          operator = "Exists"
        }
      ]
      resources = {
        requests = {
          cpu    = "50m"
          memory = "100Mi"
        }
        limits = {
          memory = "200Mi"
        }
      }
    })
  ]
}
