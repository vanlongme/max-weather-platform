# NGINX Ingress Controller Module

Installs the NGINX Ingress Controller via Helm (chart `ingress-nginx`, version `4.11.3`) into the `ingress-nginx` namespace.

Configured for:
- AWS NLB (internet-facing, IP target type) via service annotations
- IngressClass `nginx` set as the default cluster ingress
- 2 replicas for HA
- Cross-zone load balancing enabled

## Usage

```hcl
module "nginx_ingress" {
  source = "../../modules/nginx-ingress"

  chart_version = "4.11.3"
  replica_count = 2
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `chart_version` | Helm chart version. | `string` | `"4.11.3"` |
| `replica_count` | Number of controller replicas. | `number` | `2` |

## Outputs

| Name | Description |
|---|---|
| `release_name` | Helm release name. |
| `release_status` | Helm release status. |
| `namespace` | Deployment namespace. |
