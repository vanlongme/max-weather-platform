# Max Weather — DevOps Assessment

## TL;DR

Max Weather is a containerized Node.js weather API on AWS EKS, fronted by API Gateway HTTP API with a Lambda HS256 JWT authorizer. Full stack provisioned via Terraform (modular, remote state). Deployed by Jenkins declarative pipeline. KEDA ScaledObject (cpu) drives pod autoscaling; Karpenter handles workload node provisioning. Single `make teardown` returns the AWS account to zero.

## Architecture

![Architecture Diagram](docs/architecture.png)

Source: [`docs/architecture.drawio`](docs/architecture.drawio)

See [ARCHITECTURE.md](ARCHITECTURE.md) for full component breakdown, data flow, scaling design, cost estimate, and security posture.

## Deliverables

| ID | Deliverable | Location |
|----|-------------|----------|
| D1 | Architecture diagram | `docs/architecture.drawio`, `docs/architecture.png` |
| D2 | Terraform IaC (modular, remote state) | `infra/bootstrap/`, `infra/envs/poc/`, `infra/modules/` |
| D3 | K8s manifests + cluster addons (Terraform Helm) | `k8s/base/`, `k8s/overlays/`, `infra/envs/poc/eks-self-managed-addons/` |
| D4 | Jenkins CI/CD | `jenkins/pipelines/`, `jenkins/jobs.groovy`, `jenkins/README.md` |
| D5 | API GW + Lambda authorizer (HS256) | `infra/envs/poc/lambdas/authorizer/`, `scripts/api-gw-setup.sh` |
| D6 | Postman collection | `docs/postman/` |

## Prerequisites

- AWS account + CLI (admin rights, default region `us-east-1`)
- Terraform 1.6+, kubectl 1.29+, Helm 3.13+, Docker (buildx), Node.js 20+
- `newman`: `npm i -g newman`

## Quick Start

```bash
make bootstrap                              # Remote state backend (S3 + DynamoDB)
make init && make plan && make apply        # Provision all infra (~20 min)
aws eks update-kubeconfig --name max-weather --region us-east-1
make app-build-push                         # Build + push weather-api to ECR
make lambda-deps                            # Install Lambda authorizer deps
make deploy-staging                         # Apply k8s workloads (staging)
make api-gw-setup                           # Wire API Gateway + VPC Link (post-EKS)
```

## Authentication

```bash
TOKEN=$(make issue-token)
curl -H "Authorization: Bearer $TOKEN" \
  "$(cd infra/envs/poc && terraform output -raw api_gateway_invoke_url)/weather?latitude=10.78&longitude=106.70"
```

The Lambda authorizer (`infra/envs/poc/lambdas/authorizer/src/index.js`) verifies HS256 signature + scope, fetching the shared secret from Secrets Manager (cached per Lambda container lifetime).

## Teardown

```bash
make teardown
```

Runs `scripts/teardown.sh` — 10 ordered phases: kubectl delete → Karpenter drain → helm uninstall → terraform destroy. Full phase detail in [ARCHITECTURE.md](ARCHITECTURE.md).

## Security Notes

- No secrets in Git — all in Secrets Manager, mounted via External Secrets Operator
- EKS Pod Identity for all workloads (jenkins, cluster-autoscaler, fluent-bit, external-secrets, karpenter)
- Least-privilege IAM per Terraform module
- NetworkPolicies: weather-api accepts ingress only from ingress-nginx
- Public-subnet topology (POC trade-off — no NAT Gateway); inbound contained by SGs + API GW + Lambda authorizer
- ECR scan-on-push; Jenkins fails on HIGH/CRITICAL findings

## License

Assessment artifact. Third-party libraries retain original licenses.
