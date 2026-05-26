# infra/envs/poc

Main Terraform composition for the `poc` environment. Wires seven reusable
modules (`networking`, `cloudwatch`, `ecr`, `secrets`, `iam`, `eks`, `lambda`)
plus the `eks-self-managed-addons` child module into a single remote state.

## Topology

### Network — 2-tier VPC (`10.20.0.0/16`, 3 AZs)

| Subnet tier | CIDRs | Purpose |
|-------------|-------|---------|
| Public (`/24` × 3) | `10.20.1-3.0/24` | `infra` MNG nodes, IGW |
| Private (`/24` × 3) | `10.20.11-13.0/24` | Karpenter workload nodes, NAT egress |

Single NAT Gateway in `us-east-1a` (AZ-a failure breaks private egress — accepted for POC).

**VPC endpoints**: 18 interface endpoints (ec2, ecr.api, ecr.dkr, sts, logs,
eks, eks-auth, kms, sqs, autoscaling, elasticloadbalancing, ssm, ssmmessages,
ec2messages, monitoring, secretsmanager, elasticfilesystem, xray) + 1 S3 gateway
endpoint. Private DNS enabled. All interface endpoints land in private subnets.

### EKS Cluster (`poc-max-weather-cluster`, v1.34)

**Hybrid endpoint**: `private_access=true` + `public_access=true` restricted
to `allowed_cidrs` (operator `/32`). Rejects `0.0.0.0/0` via validation.
KMS CMK encrypts etcd. All 5 control-plane log types shipped to CloudWatch.

#### Node groups

| Group | Type | Subnets | Instance | Min/Max/Desired | Labels / Taints |
|-------|------|---------|----------|-----------------|-----------------|
| `infra` MNG | Managed (Bottlerocket) | **Public** | `m6i.large` | 2 / 10 / 2 | `role=infra` / `role=infra:NoSchedule` |
| Karpenter NodePool | Karpenter-provisioned | **Private** | t/m/c-family, spot+on-demand | 0 / unbounded | `role=workload` / `role=workload:NoSchedule` |

The `infra` MNG hosts platform controllers (CoreDNS, Karpenter, Jenkins,
ingress-nginx, KEDA, etc.). All controllers pin to infra nodes via
`nodeSelector: { role: infra }` and tolerate `role=infra:NoSchedule`.

Karpenter's `NodePool` provisions workload nodes in private subnets on
Bottlerocket (`EC2NodeClass`: 4 GiB OS volume + 60 GiB data volume,
IMDSv2 hop 2). The weather-api `Deployment` pins to workload nodes via
`nodeSelector: { role: workload }` and tolerates `role=workload:NoSchedule`.

#### EKS managed add-ons

CoreDNS, kube-proxy, VPC CNI, EKS Pod Identity Agent, aws-ebs-csi-driver
(creates `ebs-csi-default-sc` gp3 default `StorageClass`), aws-efs-csi-driver.
CSI drivers use EKS Pod Identity (not IRSA).

### Self-managed Helm add-ons (stage3 child module)

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

### API Gateway + Lambda authorizer

HTTP API (v2) with two stages (`staging`, `prod`). Each stage uses a per-stage
HS256 JWT secret from Secrets Manager. The Lambda authorizer (`nodejs22.x`,
128 MB, 5 s timeout) verifies signature + scope, fetching the secret from
Secrets Manager (cached per Lambda container lifetime).

## Staged apply (mandatory)

`terraform-aws-modules/eks` v21 has unknown-at-plan `count` values inside its
node-group submodule, and the `helm_release` / `kubernetes_manifest` providers
need a live cluster API at plan time. A single apply from zero fails. Use the
`make apply-all` chain (or each stage individually):

| Stage | Target flags | What it creates |
|-------|-------------|-----------------|
| `make apply-stage1` | `-target` | `module.networking` `module.cloudwatch` `module.ecr` `module.secrets` `module.iam` |
| `make apply-stage2` | `-target` | `module.eks` `module.lambda` → then `make kubeconfig` |
| `make apply-stage3` | none | `module.eks_self_managed_addons` (Helm releases + NodePool + ClusterSecretStore) |

Each stage is idempotent. Re-run a stage if it fails.

**Pre-requisite**: run `make lambda-deps` before `make init` or any `apply`
— `archive_file` zips the Lambda source at plan time and requires
`lambdas/authorizer/node_modules/` to exist.

## Usage

```bash
make bootstrap      # one-time: create tfstate S3 + DynamoDB lock
make lambda-deps    # install Lambda authorizer deps
make init           # terraform init (envs/poc/)
make apply-all      # stage1 → stage2 → stage3 (~25 min from zero)
```

Copy `terraform.tfvars.example` to `terraform.tfvars` and set `allowed_cidrs`
to your operator IP. The file is gitignored; never commit it.

```bash
cp terraform.tfvars.example terraform.tfvars
# edit allowed_cidrs = ["YOUR.IP/32"]
```

## Inputs

| Name | Default | Description |
|------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region |
| `project` | `max-weather` | Project name (forms `master_prefix` with env) |
| `vpc_cidr` | `10.20.0.0/16` | VPC CIDR |
| `availability_zones` | `["us-east-1a","us-east-1b","us-east-1c"]` | AZs |
| `public_subnet_cidrs` | `10.20.1-3.0/24` | Public subnet CIDRs (infra MNG) |
| `private_subnet_cidrs` | `10.20.11-13.0/24` | Private subnet CIDRs (Karpenter nodes) |
| `allowed_cidrs` | — **required** | Operator IP/32 for EKS public endpoint |
| `eks_cluster_version` | `1.34` | Kubernetes version |
| `log_retention_days` | `7` | CloudWatch log retention (days) |
| `enable_nat_gateway` | `true` | Single NAT GW in AZ-a |
| `enable_vpc_endpoints` | `true` | 18 interface + 1 S3 gateway endpoint |
| `eks_managed_node_groups` | `infra` group | MNG map (replaces default entirely) |
| `cluster_addons` | CoreDNS, kube-proxy, VPC CNI, Pod Identity Agent | EKS managed add-ons |
| `pod_identity_roles` | 5 built-in roles | Pod Identity IAM roles (replaces default entirely) |
| `secrets` | 3 secrets | Secrets Manager entries (replaces default entirely) |
| `lambda_functions` | `{}` | Lambda functions; wired in `main.tf` when empty |

See `variables.tf` for all inputs and `terraform.tfvars.example` for annotated
override examples.

## Outputs

| Name | Description |
|------|-------------|
| `cluster_endpoint` | EKS API server URL |
| `cluster_name` | EKS cluster name (`poc-max-weather-cluster`) |
| `ecr_repository_urls` | Map of ECR repo URLs keyed by short name |
| `api_gateway_invoke_url_staging` | API Gateway invoke URL for the staging stage |
| `api_gateway_invoke_url_prod` | API Gateway invoke URL for the prod stage |

See `outputs.tf` for the full list.

## Conventions

- `master_prefix = "${environment}-${project}"` → `poc-max-weather`. Derived
  from the directory name at plan time (`basename(path.cwd)`).
- **Map variables replace defaults entirely** — no merge. Re-declare all entries
  when overriding `eks_managed_node_groups`, `secrets`, `pod_identity_roles`,
  `lambda_functions`, `ecr_repositories`.
- `locals` blocks live only in `locals.tf`. Never inline them in `main.tf`.
- **Pod Identity over IRSA** for all new workloads (EKS 1.30+). IRSA retained
  only for legacy via `iam_irsa_roles` (empty by default).
- IMDSv2 enforced: hop limit 1 on MNG, hop limit 2 on Karpenter nodes (Pod
  Identity Agent requirement).

## Pre-commit hooks

gitleaks, `terraform_fmt`, `terraform_validate`, `end-of-file-fixer`,
`trailing-whitespace`. Run `pre-commit run --all-files` before pushing.

## Teardown

```bash
make teardown   # scripts/teardown.sh — requires confirmation phrase "destroy max-weather"
```

Destroys workloads (envs/poc) then bootstrap (S3 tfstate + DynamoDB lock) then
cloud-nuke sweeps orphans. Bootstrap S3 uses `force_destroy = true` so
`terraform destroy` works without manual edits.
