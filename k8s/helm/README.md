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
| `karpenter` | oci://public.ecr.aws/karpenter/karpenter | 1.6.0 | `kube-system` |

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
| `CLUSTER_ENDPOINT` | `module.eks.cluster_endpoint` |
| `LOG_GROUP_NAME` | `module.cloudwatch.eks_application_log_group` |
| `KARPENTER_QUEUE_NAME` | `module.eks.karpenter_queue_name` |
| `KARPENTER_NODE_IAM_ROLE_NAME` | `module.eks.karpenter_node_iam_role_name` |

> Workload IAM is bound via **EKS Pod Identity** (`aws_eks_pod_identity_association`
> in `infra/modules/eks`), not IRSA — so no `*_ROLE_ARN` placeholders appear in
> `values.yaml` and ServiceAccounts carry no `eks.amazonaws.com/role-arn`
> annotation. The five built-in associations (jenkins, cluster-autoscaler,
> fluent-bit, aws-load-balancer-controller, external-secrets) are listed in
> `infra/modules/iam/locals.tf`.

## Customization

Edit the `values.yaml` for the component you want to tune. The install script is
idempotent: re-running `make install-addons` after editing values applies the
diff (Helm computes the patch).

## Karpenter notes

Karpenter installs from the `oci://public.ecr.aws/karpenter/karpenter` chart and
ships a controller plus the `EC2NodeClass` and `NodePool` v1 CRDs. The AWS-side
scaffolding (controller IAM role via EKS Pod Identity, node IAM role + instance
profile, SQS interruption queue) is created by the EKS module wrapper
(`infra/modules/eks/main.tf`) using the upstream `terraform-aws-modules/eks`
karpenter sub-module. As of upstream v21, the controller uses EKS Pod Identity
(no ServiceAccount IRSA annotation needed) — the `EKSPodIdentityAssociation` is
created by the karpenter sub-module via `create_pod_identity_association = true`.

Coexistence with cluster-autoscaler:
- The EKS-managed `general` node group (label `role=general`) is owned by
  cluster-autoscaler and hosts the Karpenter controller pods.
- The `default` NodePool taints provisioned nodes with
  `karpenter.sh/provisioned=true:NoSchedule`. Application pods opt in by adding
  the matching toleration; everything else lands on cluster-autoscaler nodes.

## Uninstallation

`scripts/teardown.sh` runs `helm uninstall` for all seven releases before
`terraform destroy`, with Karpenter handled last so it can drain its
provisioned nodes first. To uninstall a single release manually:

```bash
helm uninstall ingress-nginx -n ingress-nginx
```
