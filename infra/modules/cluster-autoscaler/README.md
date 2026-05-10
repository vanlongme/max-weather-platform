# Cluster Autoscaler Module

Installs Cluster Autoscaler via Helm (chart version `9.37.0`, compatible with EKS 1.30) in `kube-system`.

Uses IRSA for IAM permissions (no node-role credentials). Auto-discovers ASGs tagged with `k8s.io/cluster-autoscaler/<cluster>=owned`.

## Usage

```hcl
module "cluster_autoscaler" {
  source = "../../modules/cluster-autoscaler"

  cluster_name  = "max-weather"
  aws_region    = "us-east-1"
  irsa_role_arn = module.iam.cluster_autoscaler_role_arn
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `cluster_name` | EKS cluster name for auto-discovery. | `string` | n/a |
| `aws_region` | AWS region. | `string` | n/a |
| `irsa_role_arn` | IRSA role ARN for the service account. | `string` | n/a |
| `chart_version` | Helm chart version. | `string` | `"9.37.0"` |
