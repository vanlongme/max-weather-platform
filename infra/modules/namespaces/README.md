# namespaces Module

Creates `weather-staging` and `weather-prod` Kubernetes namespaces with:
- **ResourceQuota**: CPU/memory limits per namespace (prevents one env from starving the other)
- **LimitRange**: Default container resource requests/limits
- **NetworkPolicy**: `deny-all-ingress` baseline + `allow-from-ingress-nginx`

## Usage

```hcl
module "namespaces" {
  source = "../../modules/namespaces"

  cluster_name = "max-weather"

  depends_on = [module.eks_nodegroup]
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `cluster_name` | EKS cluster name (used in labels). | `string` | — |

## Outputs

| Name | Description |
|---|---|
| `namespace_names` | List of created namespace names. |
