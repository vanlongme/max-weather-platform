# EKS Node Group Module

Creates an EKS managed node group with:

- AL2023 AMI (x86_64), ON_DEMAND capacity
- t3.medium instances (configurable), 20 GiB root disk
- Scaling: 2 min, 10 max, 2 desired (Cluster Autoscaler manages desired after initial deploy)
- Tags required for Cluster Autoscaler auto-discovery (`k8s.io/cluster-autoscaler/*`)
- Nodes placed in private subnets only

## Usage

```hcl
module "eks_nodegroup" {
  source = "../../modules/eks-nodegroup"

  cluster_name       = module.eks_cluster.cluster_name
  node_role_arn      = module.iam.eks_node_role_arn
  private_subnet_ids = module.networking.private_subnet_ids
  min_size           = 2
  max_size           = 10
  desired_size       = 2
  tags               = local.common_tags
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `cluster_name` | EKS cluster name. | `string` | n/a | yes |
| `node_role_arn` | IAM role ARN for worker nodes. | `string` | n/a | yes |
| `private_subnet_ids` | Private subnet IDs for node placement. | `list(string)` | n/a | yes |
| `instance_types` | EC2 instance types. | `list(string)` | `["t3.medium"]` | no |
| `min_size` | Minimum node count. | `number` | `2` | no |
| `max_size` | Maximum node count. | `number` | `10` | no |
| `desired_size` | Initial desired node count. | `number` | `2` | no |
| `disk_size` | Root EBS volume GiB. | `number` | `20` | no |
| `tags` | Common tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `node_group_name` | Node group name. |
| `node_group_arn` | Node group ARN. |
| `node_group_status` | Node group status. |

## Requirements

| Name | Version |
|------|---------|
| terraform | `>= 1.9, < 2.0` |
| aws | `~> 5.60` |
