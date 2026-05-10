# Max Weather — 101 Digital DevOps Assessment

## TL;DR

Max Weather is a containerized weather API on AWS EKS, fronted by API Gateway with a
Lambda authorizer that validates Cognito JWTs. The full stack is provisioned via
Terraform (multi-environment, remote state), deployed by a Jenkins declarative
pipeline (build, test, push to ECR, kubectl apply), and observable via CloudWatch
Container Insights with HPA-based autoscaling. A k6 load test demonstrates HPA
scaling end-to-end, and a single `make teardown` returns the AWS account to zero.

## Architecture

![Architecture Diagram](docs/architecture.png)

Source: [`docs/architecture.drawio`](docs/architecture.drawio)

The data plane:

1. Client obtains an OAuth2 access token from Cognito (client_credentials flow with `weather-api/read` scope).
2. Client calls `GET /weather` on the API Gateway HTTP API endpoint with `Authorization: Bearer <token>`.
3. API Gateway invokes the Lambda authorizer, which validates the JWT signature against Cognito JWKS and checks the scope.
4. On allow, API Gateway forwards the request via VPC Link to an internal Network Load Balancer.
5. The NLB targets the `ingress-nginx` Service inside EKS, which routes by Host/path to the `weather-api` Service.
6. `weather-api` pods (Node.js) call Open-Meteo and return JSON. Logs ship to CloudWatch via Fluent Bit; metrics flow to Container Insights, driving the HPA.

## Deliverables

| ID | Deliverable | Location |
|----|-------------|----------|
| D1 | Architecture diagram | `docs/architecture.drawio`, `docs/architecture.png` |
| D2 | Terraform IaC (modular, remote state) | `infra/bootstrap/`, `infra/envs/poc/`, `infra/modules/` (each module ships README.md + terraform.tfvars.example) |
| D3 | Kubernetes manifests + Helm charts | `k8s/base/`, `k8s/overlays/{staging,prod}/`, `k8s/helm/`, `scripts/install-helm-addons.sh` |
| D4 | Jenkins CI/CD pipeline | `Jenkinsfile`, `ci/README.md` |
| D5 | API Gateway + Cognito + Lambda authorizer | `infra/modules/{cognito,api-gateway,lambda-authorizer}/`, `lambda-authorizer/`, `docs/api-gateway-runbook.md` |
| D6 | Postman collection + load test | `docs/postman/`, `tests/load/weather-load.js` |

## Prerequisites

- AWS account with admin rights and a CLI profile (default region `us-east-1`)
- AWS CLI v2, Terraform 1.6+, kubectl 1.29+, Helm 3.13+, Docker (with buildx)
- Node.js 20+ (for the application and Lambda authorizer)
- `newman` (for Postman runs): `npm i -g newman newman-reporter-htmlextra`
- `k6` (for load tests): `brew install k6` or [k6 installation docs](https://k6.io/docs/getting-started/installation/)
- `cloud-nuke` (for orphan cleanup, optional): download `cloud-nuke_linux_amd64` from [Gruntwork releases](https://github.com/gruntwork-io/cloud-nuke/releases)

## Quick Start

End-to-end deployment from a clean AWS account:

```bash
# 1. Initialize remote state backend (S3 + DynamoDB)
make bootstrap

# 2. Provision all infrastructure (VPC, EKS, ECR, Cognito, Lambda, API GW)
make init
make plan
make apply        # ~20 minutes

# 3. Configure kubectl
aws eks update-kubeconfig --name max-weather --region us-east-1

# 4. Install cluster Helm add-ons (ingress-nginx, autoscaler, fluent-bit, etc.)
make install-addons

# 5. Build and push the application image
make app-build-push

# 6. Package and deploy the Lambda authorizer
make authorizer-deploy

# 7. Deploy Kubernetes workloads (re-runs install-addons idempotently)
make deploy-staging

# 7. Smoke-test through API Gateway
make postman

# 8. Run load test and capture HPA evidence
make load-test

# 9. Collect all evidence into docs/evidence/
make evidence
make verify-evidence
```

## Repository Layout

```
.
├── Jenkinsfile                  # CI/CD pipeline (declarative)
├── Makefile                     # Operator entrypoints
├── README.md                    # You are here
├── app/                         # Weather API (Node.js)
├── lambda-authorizer/           # Cognito JWT validator (Node.js)
├── infra/
│   ├── bootstrap/               # Remote state backend (S3 + DynamoDB)
│   ├── envs/
│   │   └── poc/                 # Single POC composition — hosts both weather-staging + weather-prod namespaces
│   └── modules/                 # Reusable Terraform modules (each ships README.md + terraform.tfvars.example)
│       ├── networking/          # VPC + public subnets + IGW (POC: no NAT/private subnets — see module README)
│       ├── eks/                 # Wraps terraform-aws-modules/eks/aws ~> 21.20 + Karpenter sub-module (IAM, SQS, instance profile, Pod Identity)
│       ├── ecr/                 # Container registries
│       ├── cognito/             # User Pool, App Client, Resource Server
│       ├── iam/                 # IRSA roles (jenkins, cluster-autoscaler, fluent-bit, aws-lb-controller, external-secrets)
│       ├── secrets/             # Secrets Manager seed values
│       └── cloudwatch/          # Log groups
├── k8s/
│   ├── base/                    # Kustomize base (Deployment, Service, HPA, NetworkPolicy, ResourceQuota)
│   ├── overlays/
│   │   ├── staging/             # min replicas 2, lower limits
│   │   └── prod/                # min replicas 3, higher limits
│   ├── manifests/               # Raw kubectl-applied YAML (namespaces, ResourceQuota, NetworkPolicies)
│   └── helm/                    # Helm-managed cluster addons (values.yaml per chart)
│       ├── nginx-ingress/
│       ├── cluster-autoscaler/
│       ├── fluent-bit/
│       ├── aws-lb-controller/
│       ├── external-secrets/
│       ├── metrics-server/
│       ├── jenkins/             # jenkinsci/jenkins chart, latest version at install (IRSA + ingress-nginx)
│       └── karpenter/           # Karpenter v1.6.0 chart values + EC2NodeClass + NodePool
├── ci/                          # Jenkins README
├── docs/
│   ├── architecture.drawio      # Source diagram
│   ├── architecture.png         # Rendered diagram
│   ├── api-gateway-runbook.md   # Manual API Gateway / VPC Link / Authorizer wiring
│   ├── postman/                 # Postman collection + env template
│   └── evidence/                # Captured evidence (terraform, k8s, k6, CloudWatch, teardown — populated by `make evidence`)
├── tests/
│   └── load/weather-load.js     # k6 load test
└── scripts/                     # Operational scripts
    ├── get-token.sh
    ├── run-postman.sh
    ├── run-loadtest.sh
    ├── force-scale-demo.sh
    ├── collect-evidence.sh
    ├── verify-evidence.sh
    ├── sanitize-outputs.sh
    ├── install-helm-addons.sh
    ├── teardown.sh
    └── cloud-nuke-wrapper.sh
```

## Configuration

Per-environment Terraform variables live in `infra/envs/poc/terraform.tfvars`
(copy from `terraform.tfvars.example` and fill in your operator IP and Cognito
domain prefix). The single `poc` env hosts both `weather-staging` and
`weather-prod` Kubernetes namespaces in one cluster.
Key variables:

| Variable | Purpose | Example |
|----------|---------|---------|
| `region` | AWS region | `us-east-1` |
| `project` | Tag prefix and resource name component | `max-weather` |
| `environment` | Env name (used in tags and DNS) | `staging` |
| `vpc_cidr` | VPC IPv4 CIDR | `10.20.0.0/16` |
| `azs` | Availability zones | `["us-east-1a","us-east-1b"]` |
| `eks_version` | Kubernetes minor | `1.29` |
| `node_instance_types` | Worker EC2 instance types | `["t3.medium"]` |
| `node_desired_capacity` | Initial worker count | `2` |
| `node_min_size` / `node_max_size` | Autoscaling bounds | `2` / `5` |
| `cognito_domain_prefix` | Cognito hosted UI subdomain | `max-weather-staging` |
| `tags` | Common tags applied to all resources | `{ Project = "max-weather", Env = "staging" }` |

All resources are tagged with `Project=max-weather` so cost and cleanup queries
can scope to this assessment.

## Cost Estimate

Steady-state monthly cost (us-east-1, on-demand pricing) for the POC stack
(public-subnet topology — no NAT GW, no VPC endpoints):

| Service | Monthly USD |
|---------|-------------|
| EKS control plane | 73 |
| 2 x t3.medium worker nodes | 60 |
| NLB (created by ingress-nginx Service, internet-facing) | 18 |
| ECR storage (~5 GB) | 1 |
| CloudWatch Logs (5 log groups, ~5 GB ingest) | 8 |
| Container Insights metrics | 5 |
| Lambda authorizer (free tier) | 0 |
| API Gateway HTTP API (low volume) | 1 |
| Cognito (under MAU limit) | 0 |
| Secrets Manager (5 secrets) | 2 |
| Jenkins (in-cluster pod, 8Gi gp3 PVC) | 1 |
| **Total** | **~169** |

POC topology savings vs a production-style network:

| Removed | Monthly USD saved |
|---------|-------------------|
| NAT Gateway (1) + data processing | ~35 |
| 3 x Interface VPC Endpoints (ECR API/DKR + Logs) | ~21 |

For a 2-day demo (`apply` -> evaluate -> `teardown`), prorated cost is ~$12.
Run `make teardown` immediately after evaluation to avoid drift.

## Authentication

The API uses Cognito **client_credentials** flow (machine-to-machine), not user login.

```bash
TOKEN=$(scripts/get-token.sh)
curl -H "Authorization: Bearer $TOKEN" \
  "$(cd infra/envs/poc && terraform output -raw api_gateway_invoke_url)/weather?latitude=10.78&longitude=106.70"
```

The Lambda authorizer (`lambda-authorizer/src/index.js`):

1. Extracts `Bearer <jwt>` from the `Authorization` header.
2. Fetches Cognito JWKS (cached in memory across invocations).
3. Verifies signature, expiry, audience (client_id), and `scope` includes `weather-api/read`.
4. Returns `{ isAuthorized: true|false }`.

JWT validation is offline (no network calls per invoke), so cold-start tail latency
stays under 1s and warm latency is < 10ms.

## Observability

CloudWatch log groups (one per workload, 7-day retention by default):

| Group | Source |
|-------|--------|
| `/aws/eks/max-weather/cluster` | EKS control plane (api, audit, authenticator) |
| `/aws/eks/max-weather/application` | Pod stdout/stderr via Fluent Bit DaemonSet |
| `/aws/lambda/max-weather-authorizer` | Lambda authorizer invocation logs |
| `/aws/apigateway/max-weather-api` | API Gateway access logs |
| `/aws/eks/max-weather/host` | Node-level systemd / kubelet via Fluent Bit |

Container Insights provides per-pod CPU/memory/network metrics under the
`ContainerInsights` namespace, dimensioned by `ClusterName` and `Namespace`.

Live troubleshooting:

```bash
kubectl get hpa -n weather-staging -w
kubectl top pods -n weather-staging
kubectl logs -n weather-staging -l app=weather-api --tail=100 -f
aws logs tail /aws/eks/max-weather/application --follow --region us-east-1
```

## Cluster Autoscaling: Cluster Autoscaler + Karpenter

The cluster runs **both** node autoscalers side-by-side, with strict separation of duties:

| Autoscaler | Manages | Why both? |
|------------|---------|-----------|
| **Cluster Autoscaler** (`9.37.0`) | The static `general` Managed Node Group (min 2, max 10 t3.medium) that hosts system pods (kube-system, ingress-nginx, autoscalers themselves) | Provides a stable baseline so cluster-critical pods always have somewhere to land, including Karpenter's controller itself |
| **Karpenter** (`v1.6.0`) | All other workload pods via `NodePool` / `EC2NodeClass` (on-demand t3.medium-large, AL2023) | Faster scale-up (~30s vs ~3min), bin-packing, and consolidation — ideal for the bursty `weather-api` HPA |

**Coexistence mechanism**: Karpenter's `NodePool` taints every node it provisions with `karpenter.sh/provisioned=true:NoSchedule`. The Karpenter controller pod uses `nodeSelector: role=general` to pin itself onto the Managed Node Group, breaking the chicken-and-egg problem. Cluster Autoscaler ignores tainted nodes; Karpenter ignores the Managed Node Group.

**AWS scaffolding** (provisioned by `infra/modules/eks` via the upstream `terraform-aws-modules/eks/aws//modules/karpenter` sub-module):

- IAM role `<cluster>-karpenter-controller` (IRSA) — controller permissions
- IAM role `<cluster>-karpenter-node` + EC2 instance profile — assumed by provisioned instances
- SQS queue `<cluster>-karpenter` — receives EC2 spot interruption / health events
- EventBridge rules forwarding instance-state events into the queue

The Helm chart and Kubernetes objects (`NodePool`, `EC2NodeClass`) live in `k8s/helm/karpenter/` and are installed by `scripts/install-helm-addons.sh` step 7. The `EC2NodeClass.role` field references the IAM role name above via envsubst (`${KARPENTER_NODE_IAM_ROLE_NAME}`), so renaming the cluster automatically renames the role and the EC2NodeClass stays in sync. See `k8s/helm/README.md` for the full env-var contract.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `terraform apply` fails on EKS with "cluster does not exist" | aws-auth ConfigMap not yet propagated | Wait 60s, re-run `terraform apply` |
| `kubectl` returns "Unauthorized" | kubeconfig points at the wrong context | Re-run `aws eks update-kubeconfig --name max-weather --region us-east-1` |
| Pods stuck in `ImagePullBackOff` | ECR image not pushed, or node IAM lacks `ecr:GetAuthorizationToken` | Run `make app-build-push`; verify the node group IAM role attaches `AmazonEC2ContainerRegistryReadOnly` |
| API Gateway returns 401 | JWT expired (1h TTL) or scope missing | Re-run `scripts/get-token.sh`; check the App Client has `weather-api/read` scope |
| API Gateway returns 502 | VPC Link target group unhealthy | Verify NLB targets are healthy: `aws elbv2 describe-target-health --target-group-arn <arn>` |
| HPA not scaling under load | Open-Meteo upstream is caching, so pod CPU stays low | Run `bash scripts/force-scale-demo.sh` to demonstrate scaling wiring |
| `terraform destroy` hangs on subnet deletion | Orphaned ENI from NLB or Lambda | Wait 5 minutes for ENI cleanup, then re-run; or use `make cloud-nuke-dry` to identify |
| Newman exits non-zero with "ECONNREFUSED" | `invoke_url` not yet propagated, or wrong stage | Confirm the API Gateway stage is deployed: `aws apigatewayv2 get-stages --api-id <id>` |

## Teardown

Single command, ordered to avoid leaving orphans:

```bash
make teardown
```

This runs `scripts/teardown.sh` which executes 10 phases in order:

1. Confirms intent (operator must type `destroy max-weather`).
2. `kubectl delete -k k8s/overlays/{staging,prod}` to remove ingress (triggers NLB cleanup).
3. Drains Karpenter-provisioned nodes by deleting `NodePool`/`EC2NodeClass`/`NodeClaim` so Karpenter terminates EC2 before its IAM role disappears.
4. Sleeps 60s for AWS Load Balancer Controller to delete target groups.
5. `helm uninstall` for all 8 releases: ingress-nginx, AWS LB Controller, Cluster Autoscaler, Fluent Bit, External Secrets, Metrics Server, Jenkins, Karpenter (Karpenter last, after its workloads drain).
6. `kubectl delete ns` for application and system namespaces.
7. Prompts for manual API Gateway deletion (it was created out-of-band per `docs/api-gateway-runbook.md`).
8. `terraform destroy -auto-approve` in `infra/envs/poc` (destroys EKS, Karpenter SQS/IAM, VPC, etc.).
9. Optional: cloud-nuke dry-run to surface any orphaned resources.
10. Prints elapsed time and savings.

For state-backend cleanup (rare):

```bash
cd infra/bootstrap && terraform destroy -auto-approve
```

To verify zero remaining resources tagged with `Project=max-weather`:

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=max-weather \
  --region us-east-1 \
  --query 'ResourceTagMappingList[].ResourceARN' --output text
```

## Security Notes

- **No secrets in Git.** All secrets (Cognito client_secret, third-party API keys) live in AWS Secrets Manager and are mounted into pods via External Secrets Operator. The Postman environment template ships with empty secret fields.
- **IRSA everywhere.** Workload pods (Cluster Autoscaler, AWS LB Controller, Fluent Bit, External Secrets, weather-api) use IAM Roles for Service Accounts — no node-level IAM credentials shared across pods.
- **Least-privilege IAM.** Each module owns its own IAM role with policies scoped to the resources it manages.
- **Network isolation (POC trade-off).** This POC places worker nodes in **public subnets** (each gets a public IPv4) so that ECR / Cognito / Open-Meteo egress works without a NAT Gateway. Inbound exposure is contained by Security Groups (SSH never opened publicly; the EKS API endpoint is locked to `var.allowed_cidrs`; the ingress-nginx NLB is the only intentionally public entry point and is itself fronted by API Gateway + the Cognito-backed Lambda authorizer). For production, switch to private subnets + NAT Gateway (or VPC endpoints for ECR/Logs/STS) and flip the ingress-nginx Service annotation back to `internal`. The networking module ships both `kubernetes.io/role/elb` and `kubernetes.io/role/internal-elb` tags so the production overlay can place internal NLBs without re-tagging.
- **NetworkPolicies.** `weather-api` pods accept ingress only from `ingress-nginx` and egress only to DNS, Cognito JWKS, and Open-Meteo.
- **JWT verified offline.** The Lambda authorizer caches Cognito JWKS in memory; signature verification is local.
- **Image scanning.** ECR repositories have scan-on-push enabled. The Jenkins pipeline fails on `HIGH`/`CRITICAL` findings.
- **Sanitized outputs.** `scripts/sanitize-outputs.sh` strips `sensitive=true` Terraform outputs and redacts AWS account IDs / JWT-like strings before any `terraform output` artifact is committed to evidence.

## Out of Scope

- Multi-region deployment (single `us-east-1`)
- Production-grade WAF and DDoS protection (Shield Advanced)
- Custom DNS / TLS via Route53 + ACM (the API uses the default `*.execute-api` domain)
- ArgoCD / GitOps continuous deployment (Jenkins push-style is used)
- Cost anomaly detection / budgets (operator runs `make teardown` instead)
- Service mesh (Istio/Linkerd) — not needed at one-service scale

## License

This repository is submitted as an assessment artifact. All third-party libraries
retain their original licenses (MIT for Node.js dependencies, Apache 2.0 for the
AWS Load Balancer Controller, etc.). The Open-Meteo API is consumed under their
free-tier terms.
