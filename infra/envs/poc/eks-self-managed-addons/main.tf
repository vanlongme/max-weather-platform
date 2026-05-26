resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.chart_versions["ingress-nginx"]
  namespace        = "ingress-nginx"
  create_namespace = true
  values           = [file("${path.module}/values/ingress-nginx.yaml")]
}

resource "helm_release" "cluster_autoscaler" {
  name             = "cluster-autoscaler"
  repository       = "https://kubernetes.github.io/autoscaler"
  chart            = "cluster-autoscaler"
  version          = var.chart_versions["cluster-autoscaler"]
  namespace        = "kube-system"
  create_namespace = false
  values = [templatefile("${path.module}/values/cluster-autoscaler.yaml", {
    CLUSTER_NAME = var.cluster_name
    AWS_REGION   = var.aws_region
  })]
}

resource "helm_release" "fluent_bit" {
  name             = "fluent-bit"
  repository       = "https://fluent.github.io/helm-charts"
  chart            = "fluent-bit"
  version          = var.chart_versions["fluent-bit"]
  namespace        = "amazon-cloudwatch"
  create_namespace = true
  values = [templatefile("${path.module}/values/fluent-bit.yaml", {
    AWS_REGION     = var.aws_region
    LOG_GROUP_NAME = var.log_group_name
  })]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.chart_versions["external-secrets"]
  namespace        = "external-secrets"
  create_namespace = true
  values           = [file("${path.module}/values/external-secrets.yaml")]
}

resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server"
  chart            = "metrics-server"
  version          = var.chart_versions["metrics-server"]
  namespace        = "kube-system"
  create_namespace = false
  values           = [file("${path.module}/values/metrics-server.yaml")]
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.chart_versions["karpenter"]
  namespace        = "kube-system"
  create_namespace = false
  values = [templatefile("${path.module}/values/karpenter.yaml", {
    CLUSTER_NAME         = var.cluster_name
    CLUSTER_ENDPOINT     = var.cluster_endpoint
    KARPENTER_QUEUE_NAME = var.karpenter_queue_name
  })]
  depends_on = [helm_release.cluster_autoscaler]
}

resource "helm_release" "jenkins" {
  name             = "jenkins"
  repository       = "https://charts.jenkins.io"
  chart            = "jenkins"
  version          = var.chart_versions["jenkins"]
  namespace        = "jenkins"
  create_namespace = true
  values = [templatefile("${path.module}/values/jenkins.yaml", {
    CLUSTER_NAME = var.cluster_name
  })]
}

# Standalone PVC for trivy vulnerability DB cache, mounted by ephemeral
# kubernetes-plugin agent pods (claimName: trivy-db-cache in ci.Jenkinsfile).
# The jenkinsci/jenkins Helm chart does NOT support creating extra PVCs
# outside the controller STS (persistence.volumes only adds volumes to the
# controller pod, not new PVCs). RWO accepted — POC runs one CI build at a
# time; parallel builds would block on the volume.
resource "kubectl_manifest" "jenkins_trivy_db_cache_pvc" {
  yaml_body  = file("${path.module}/values/jenkins-trivy-db-cache-pvc.yaml")
  depends_on = [helm_release.jenkins]
}

resource "helm_release" "keda" {
  count            = var.enable_keda ? 1 : 0
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.chart_versions["keda"]
  namespace        = "keda"
  create_namespace = true
  values           = [file("${path.module}/values/keda.yaml")]
}

resource "kubectl_manifest" "cluster_secret_store_aws" {
  yaml_body = templatefile("${path.module}/values/external-secrets-clustersecretstore.yaml", {
    AWS_REGION = var.aws_region
  })
  depends_on = [helm_release.external_secrets]
}

resource "kubectl_manifest" "karpenter_ec2nodeclass_default" {
  yaml_body = templatefile("${path.module}/values/karpenter-ec2nodeclass.yaml", {
    CLUSTER_NAME                 = var.cluster_name
    KARPENTER_NODE_IAM_ROLE_NAME = var.karpenter_node_iam_role_name
    PRIVATE_SUBNET_IDS_YAML      = join("\n", [for id in var.private_subnet_ids : "    - id: ${id}"])
  })
  depends_on = [helm_release.karpenter, helm_release.external_secrets]
}

resource "kubectl_manifest" "karpenter_nodepool_default" {
  yaml_body  = file("${path.module}/values/karpenter-nodepool.yaml")
  depends_on = [kubectl_manifest.karpenter_ec2nodeclass_default]
}
