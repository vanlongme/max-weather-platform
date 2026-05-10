# EKS Cluster Module

Creates an EKS control plane (v1.30) with:

- Public + private endpoint access (public restricted to `allowed_cidrs`)
- Full control-plane logging: api, audit, authenticator, controllerManager, scheduler
- IAM OIDC provider (thumbprint derived via TLS certificate data source)
- Core managed add-ons: vpc-cni, coredns, kube-proxy (versions auto-resolved for k8s 1.30)
- Access entries: operator (cluster-admin) + Jenkins (namespace Edit on weather-staging/weather-prod)

## Usage

```hcl
module "eks_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name           = "max-weather"
  cluster_version        = "1.30"
  cluster_role_arn       = module.iam.eks_cluster_role_arn
  subnet_ids             = concat(module.networking.public_subnet_ids, module.networking.private_subnet_ids)
  allowed_cidrs          = ["YOUR_IP/32"]
  operator_principal_arn = data.aws_caller_identity.current.arn
  jenkins_role_arn       = module.iam.jenkins_role_arn
  tags                   = local.common_tags
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `cluster_name` | EKS cluster name. | `string` | n/a | yes |
| `cluster_version` | Kubernetes version. | `string` | `"1.30"` | no |
| `cluster_role_arn` | IAM role ARN for EKS control plane. | `string` | n/a | yes |
| `subnet_ids` | All subnet IDs (public + private) for the control plane. | `list(string)` | n/a | yes |
| `allowed_cidrs` | CIDR blocks for public API access. Must not include 0.0.0.0/0. | `list(string)` | n/a | yes |
| `operator_principal_arn` | Principal ARN for cluster-admin access entry. | `string` | n/a | yes |
| `jenkins_role_arn` | Jenkins role ARN for namespace-Edit access entry. | `string` | n/a | yes |
| `tags` | Common tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_name` | EKS cluster name. |
| `cluster_endpoint` | API server endpoint URL. |
| `cluster_ca_data` | Base64-encoded CA cert. |
| `cluster_version` | Kubernetes version. |
| `cluster_oidc_issuer_url` | OIDC issuer URL. |
| `oidc_provider_arn` | ARN of the IAM OIDC provider. |
| `oidc_provider_url` | OIDC URL without https:// (for IRSA trust policies). |
| `cluster_security_group_id` | Control-plane security group ID. |

## Requirements

| Name | Version |
|------|---------|
| terraform | `>= 1.9, < 2.0` |
| aws | `~> 5.60` |
| tls | `~> 4.0` |
