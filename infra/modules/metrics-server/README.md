# metrics-server Module

Installs the Kubernetes Metrics Server via Helm (chart `metrics-server`, version `3.12.1`) into the `kube-system` namespace.

Required for Horizontal Pod Autoscaler (HPA) to function — provides CPU/memory resource metrics.

## Usage

```hcl
module "metrics_server" {
  source = "../../modules/metrics-server"

  chart_version = "3.12.1"

  depends_on = [module.eks_nodegroup]
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `chart_version` | Helm chart version. | `string` | `"3.12.1"` |

## Outputs

| Name | Description |
|---|---|
| `release_name` | Helm release name. |
| `release_status` | Helm release status. |
| `namespace` | Deployment namespace (`kube-system`). |
