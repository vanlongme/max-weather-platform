# Max Weather — DevOps Assessment

## TL;DR

Max Weather is a containerized Node.js weather API on AWS EKS, fronted by API Gateway HTTP API with a Lambda HS256 JWT authorizer. Full stack provisioned via Terraform (modular, remote state). Deployed by Jenkins declarative pipeline. KEDA ScaledObject (cpu) drives pod autoscaling; Karpenter handles workload node provisioning. Single `make teardown` returns the AWS account to zero.

## Architecture

![Architecture Diagram](docs/architecture.png)

Source: [`docs/architecture.drawio`](docs/architecture.drawio)

See [ARCHITECTURE.md](ARCHITECTURE.md) for full component breakdown, data flow, scaling design, cost estimate, and security posture.

## Repository Layout

```
.
├── app/                 # Node.js weather API source (Dockerfile, src/, Jest tests, ESLint)
├── docs/                # Architecture diagram (drawio/png), Postman collection, evidence
├── infra/               # Terraform IaC
│   ├── bootstrap/       #   Remote-state backend: S3 tfstate bucket + DynamoDB lock table
│   ├── envs/            #   Per-env root modules (poc: VPC, EKS, addons, lambdas, API GW)
│   └── modules/         #   Reusable modules (networking, eks, ecr, iam, api_gateway, …)
├── jenkins/             # Declarative pipelines (Jenkinsfile) + Job DSL (jobs.groovy)
├── k8s/                 # Kustomize manifests (base/ + overlays/staging|prod, manifests/)
├── scripts/             # Operational helpers (issue-token.sh, teardown.sh)
├── tests/               # KEDA scale tests, k6 load tests, Playwright E2E
├── ARCHITECTURE.md      # Deep-dive: components, data flow, scaling, cost, security
├── Makefile             # Entry points: bootstrap, init, apply-all, app-build-push, teardown
├── .cloud-nuke.yaml     # cloud-nuke config — final teardown sweep of `*max-weather*`
└── README.md
```

## Prerequisites

- AWS account + CLI (admin rights, default region `us-east-1`)
- Terraform 1.6+, kubectl 1.29+, Helm 3.13+, Docker (buildx), Node.js 20+
- `newman`: `npm i -g newman`

## Quick Start

```bash
make bootstrap          # Remote state backend (S3 + DynamoDB)
make lambda-deps        # Install Lambda authorizer deps (required before init/apply)
make init               # terraform init
make apply-all          # Staged apply: foundation → EKS → addons (~25 min from zero)
make app-build-push     # Build + push weather-api to ECR
make deploy-staging     # Apply k8s workloads (staging)
# API Gateway is managed by Terraform (module: infra/modules/api_gateway/) — no manual setup
```

**Why staged apply?** `terraform-aws-modules/eks` v21 uses values unknown at plan time inside its node-group submodule (`count` argument), and the `kubernetes_manifest` / `helm_release` providers require a live cluster API at plan time. A single `terraform apply` cannot bootstrap from zero. `make apply-all` chains three stages:

1. `make apply-stage1` — foundation (VPC, IAM, ECR, Secrets, CloudWatch)
2. `make apply-stage2` — EKS cluster (incl. EBS+EFS CSI add-ons with Pod Identity; EBS driver creates `ebs-csi-default-sc` gp3 default `StorageClass`) + Lambda authorizer, then updates kubeconfig
3. `make apply-stage3` — cluster addons (helm releases + Karpenter NodePool)

Run individual stages if a step fails; each is idempotent.

## Authentication

```bash
TOKEN=$(scripts/issue-token.sh --env staging)  # Use --env prod for the production stage
curl -H "Authorization: Bearer $TOKEN" \
  "$(cd infra/envs/poc && terraform output -raw api_gateway_invoke_url_staging)/weather?latitude=10.78&longitude=106.70"
```

> **Note**: Direct script invocation only. `make issue-token` is **deprecated** post-multi-env update — the Make target does not forward the required `--env` flag and will exit 2 with usage. Use `bash scripts/issue-token.sh --env staging` (or `--env prod`) directly.

The Lambda authorizer (`infra/envs/poc/lambdas/authorizer/src/index.js`) verifies HS256 signature + scope, fetching the shared secret from Secrets Manager (cached per Lambda container lifetime).

## Teardown

```bash
make teardown
```

Runs `scripts/teardown.sh` — 10 ordered phases: kubectl delete → Karpenter drain → helm uninstall → namespace cleanup → `terraform destroy` (workload + bootstrap). The final phase shells out to **[cloud-nuke](https://github.com/gruntwork-io/cloud-nuke)** (`./cloud-nuke_linux_amd64 aws --config .cloud-nuke.yaml --force`) to sweep every remaining AWS resource matching `*max-weather*` (incl. tfstate S3 bucket + tflock DynamoDB), guaranteeing the account returns to zero even if Terraform leaves stragglers. Full phase detail in [ARCHITECTURE.md](ARCHITECTURE.md).

## License

Assessment artifact. Third-party libraries retain original licenses.
