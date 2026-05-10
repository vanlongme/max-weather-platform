# AWS Load Balancer Controller Module

Installs the AWS Load Balancer Controller via Helm (chart version `1.8.2`) in `kube-system`.

Required for NLB IP-target-type provisioning via NGINX Ingress Controller service annotations.

## Usage

```hcl
module "aws_lb_controller" {
  source = "../../modules/aws-lb-controller"

  cluster_name  = "max-weather"
  aws_region    = "us-east-1"
  vpc_id        = module.networking.vpc_id
  irsa_role_arn = module.iam.aws_lb_controller_role_arn
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `cluster_name` | EKS cluster name. | `string` | n/a |
| `aws_region` | AWS region. | `string` | n/a |
| `vpc_id` | VPC ID. | `string` | n/a |
| `irsa_role_arn` | IRSA role ARN. | `string` | n/a |
| `chart_version` | Helm chart version. | `string` | `"1.8.2"` |
| `replica_count` | Number of replicas. | `number` | `2` |
