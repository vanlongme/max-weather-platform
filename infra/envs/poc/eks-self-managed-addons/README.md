# eks-self-managed-addons

Terraform module installing self-managed Helm addons into the EKS cluster.

## Addons

| Chart | Version | Namespace |
|-------|---------|-----------|
| ingress-nginx | 4.11.3 | ingress-nginx |
| cluster-autoscaler | 9.37.0 | kube-system |
| aws-for-fluent-bit | 0.1.34 | amazon-cloudwatch |
| external-secrets | 0.10.4 | external-secrets |
| metrics-server | 3.12.1 | kube-system |
| karpenter | 1.6.0 | kube-system |
| jenkins | 5.7.16 | jenkins |
| keda | 2.15.2 | keda |

## Usage

Called from `infra/envs/poc/main.tf` after `module.eks`.
