# Cluster Add-ons (Helm)

Helm-managed Kubernetes add-ons installed onto the EKS cluster after Terraform
provisions the AWS substrate. Each component is managed via raw `helm upgrade
--install` (no Terraform `helm_release` resources) for clean separation between
AWS infrastructure (Terraform) and in-cluster workloads (Helm/kubectl).

## Components

| Chart | Repository | Version | Namespace |
|-------|------------|---------|-----------|
| `ingress-nginx` | https://kubernetes.github.io/ingress-nginx | 4.11.3 | `ingress-nginx` |
| `cluster-autoscaler` | https://kubernetes.github.io/autoscaler | 9.37.0 | `kube-system` |
| `aws-for-fluent-bit` | https://aws.github.io/eks-charts | 0.1.34 | `amazon-cloudwatch` |
| `aws-load-balancer-controller` | https://aws.github.io/eks-charts | 1.8.2 | `kube-system` |
| `external-secrets` | https://charts.external-secrets.io | 0.10.4 | `external-secrets` |
| `metrics-server` | https://kubernetes-sigs.github.io/metrics-server | 3.12.1 | `kube-system` |

## Installation

The `scripts/install-helm-addons.sh` driver reads each `values.yaml`, substitutes
environment-specific values from `terraform output`, and runs `helm upgrade
--install`:

```bash
make install-addons
```

This is run automatically:

- After `make apply` in the operator quick-start
- As a dedicated stage in the Jenkins pipeline (`Install Cluster Addons`)

## Templated Values

Some files contain `${VAR}` placeholders substituted by the install script using
`envsubst`. The required variables (sourced from `terraform output -json`) are:

| Variable | Source |
|----------|--------|
| `CLUSTER_NAME` | constant (`max-weather`) |
| `AWS_REGION` | constant (`us-east-1`) |
| `VPC_ID` | `module.networking.vpc_id` |
| `LOG_GROUP_NAME` | `module.cloudwatch.eks_application_log_group` |
| `CLUSTER_AUTOSCALER_ROLE_ARN` | `module.iam.cluster_autoscaler_role_arn` |
| `FLUENT_BIT_ROLE_ARN` | `module.iam.fluent_bit_role_arn` |
| `AWS_LB_CONTROLLER_ROLE_ARN` | `module.iam.aws_lb_controller_role_arn` |
| `EXTERNAL_SECRETS_ROLE_ARN` | `module.iam.external_secrets_role_arn` |

## Customization

Edit the `values.yaml` for the component you want to tune. The install script is
idempotent: re-running `make install-addons` after editing values applies the
diff (Helm computes the patch).

## Uninstallation

`scripts/teardown.sh` runs `helm uninstall` for all six releases before
`terraform destroy`. To uninstall a single release manually:

```bash
helm uninstall ingress-nginx -n ingress-nginx
```
