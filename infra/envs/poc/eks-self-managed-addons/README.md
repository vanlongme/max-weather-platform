# eks-self-managed-addons

Terraform module installing self-managed Helm addons + cluster-scoped
Kubernetes manifests (StorageClasses, Karpenter NodePool) into the EKS cluster
after the control plane is up.

## Addons

| Chart | Version | Namespace |
|-------|---------|-----------|
| ingress-nginx | 4.15.1 | ingress-nginx |
| cluster-autoscaler | 9.57.0 | kube-system |
| fluent-bit | 0.57.3 | amazon-cloudwatch |
| external-secrets | 2.4.1 | external-secrets |
| metrics-server | 3.13.0 | kube-system |
| karpenter | 1.12.0 | kube-system |
| jenkins | 5.9.18 | jenkins |
| keda | 2.19.0 | keda |

> The `aws-ebs-csi-driver` and `aws-efs-csi-driver` add-ons are NOT installed
> here — they are managed EKS add-ons created by `module.eks` with EKS Pod
> Identity, so they roll with the cluster and inherit AWS-vetted defaults.

## Kubernetes manifests

| Manifest | Purpose |
|----------|---------|
| `ClusterSecretStore` (external-secrets) | Cluster-wide store fronting AWS Secrets Manager + SSM Parameter Store. |
| Karpenter `EC2NodeClass` (default) | Bottlerocket AMI, dual EBS volumes (4Gi OS + 60Gi data), IMDSv2 hop 2. |
| Karpenter `NodePool` (default) | Spot + on-demand t/m/c-family instances. |

`ebs-csi-default-sc` (gp3, `WaitForFirstConsumer`, marked default) is the
cluster's default `StorageClass`. It is created by the `aws-ebs-csi-driver`
add-on itself via `configuration_values.defaultStorageClass.enabled = true`
— not by this module — so the EBS CSI rollout owns its own SC lifecycle.
The EKS managed add-on schema does not expose `storageClasses[]` (unlike the
upstream Helm chart), so the SC name is fixed to `ebs-csi-default-sc`.

The `aws-efs-csi-driver` add-on + its IAM role (via Pod Identity) are
installed so workloads can mount EFS file systems if/when one is provisioned
out-of-band; no EFS file system is created by this repo.

## Usage

Called from `infra/envs/poc/main.tf` after `module.eks`.
