# Architecture Reference

## 1. Overview

Max Weather is a containerized Node.js weather API on AWS EKS, fronted by an API Gateway HTTP API with a Lambda HS256 JWT authorizer. Cluster addons (ingress-nginx, KEDA, Karpenter, Fluent Bit, External Secrets, Jenkins, metrics-server, cluster-autoscaler) are Terraform-managed via Helm provider in `infra/envs/poc/eks-self-managed-addons/`. See the [architecture diagram](docs/architecture.png).

## 2. Data Plane Flow

1. **Client** issues HS256 JWT via `make issue-token` (reads shared secret from Secrets Manager).
2. **Client → API GW HTTP API** — `Authorization: Bearer <token>` header on `GET /weather`.
3. **API GW → Lambda Authorizer** — verifies HS256 signature + `scope: weather-api/read`; returns `{isAuthorized: true|false}`. `/healthz` route is NONE auth (unauthenticated).
4. **API GW → VPC Link → NLB (internal)** — HTTP proxy integration over private VPC link.
5. **NLB → ingress-nginx → weather-api** — L7 routing by Host/path inside EKS cluster.
6. **weather-api → Open-Meteo** — external upstream API call; JSON response returned to client.

## 3. Components

| Component | Type | Location | Purpose |
|-----------|------|----------|---------|
| EKS Cluster | AWS managed K8s | `infra/modules/eks/` | Container orchestration |
| API Gateway HTTP API | AWS managed | `scripts/api-gw-setup.sh` | Public entry point + auth gateway |
| Lambda Authorizer | AWS Lambda (Node.js) | `infra/envs/poc/lambdas/authorizer/` | HS256 JWT verification |
| NLB (internal) | AWS NLB | Created by ingress-nginx Service | Routes API GW → EKS |
| ingress-nginx | Helm release | `eks-self-managed-addons/values/ingress-nginx.yaml` | L7 routing inside EKS |
| KEDA ScaledObject | CRD (keda.sh/v1alpha1) | `k8s/base/scaledobject.yaml` | CPU-based pod autoscaling (Utilization=60) |
| Karpenter | Helm release + CRDs | `eks-self-managed-addons/values/karpenter.yaml` | Workload node provisioning |
| Cluster Autoscaler | Helm release | `eks-self-managed-addons/values/cluster-autoscaler.yaml` | System MNG autoscaling |
| Fluent Bit | Helm release | `eks-self-managed-addons/values/aws-for-fluent-bit.yaml` | Log shipping to CloudWatch |
| External Secrets | Helm release | `eks-self-managed-addons/values/external-secrets.yaml` | Secrets Manager → K8s Secrets |
| metrics-server | Helm release | `eks-self-managed-addons/values/metrics-server.yaml` | CPU/memory metrics for KEDA |
| Jenkins | Helm release | `eks-self-managed-addons/values/jenkins.yaml` | CI/CD server in-cluster |
| Secrets Manager | AWS | Terraform-created | JWT shared secret, API keys |
| ECR | AWS | `infra/modules/ecr/` | Container image registry |
| CloudWatch | AWS | `infra/modules/cloudwatch/` | Logs + Container Insights |

## 4. Scaling

**Pod scaling (KEDA):** `k8s/base/scaledobject.yaml` defines a `ScaledObject` with `type: cpu`, `metricType: Utilization`, `value: "60"`. KEDA generates a managed HPA (`keda-hpa-weather-api`) that scales weather-api pods between `minReplicaCount: 2` (staging) / `3` (prod) and `maxReplicaCount: 10`. Scale-up: 0s stabilization, +2 pods/60s. Scale-down: 300s stabilization.

**Node scaling (Karpenter):** Provisions on-demand t3.medium/large EC2 nodes (AL2023) via `NodePool`/`EC2NodeClass` CRDs applied by Terraform (`kubernetes_manifest`). Faster than Cluster Autoscaler (~30s vs ~3min). Handles workload pod burst.

**System node scaling (Cluster Autoscaler):** Manages the static `general` Bottlerocket MNG (min 1, max 10 t3.medium init workers). Hosts kube-system pods including Karpenter's own controller.

## 5. Cost Estimate

Steady-state monthly (us-east-1, on-demand):

| Service | USD/mo |
|---------|--------|
| EKS control plane | 73 |
| 1× t3.medium init worker | 30 |
| NLB (ingress-nginx) | 18 |
| ECR (~5 GB) | 1 |
| CloudWatch Logs | 8 |
| Container Insights | 5 |
| Lambda authorizer (free tier) | 0 |
| API Gateway HTTP API | 1 |
| Secrets Manager (5 secrets) | 2 |
| Jenkins PVC (8Gi gp3) | 1 |
| **Total** | **~139** |

2-day demo cost ≈ $12. Run `make teardown` immediately after evaluation.

## 6. Security Posture

- **No secrets in Git.** JWT shared secret and API keys in Secrets Manager, synced to K8s via External Secrets Operator.
- **EKS Pod Identity.** All workloads (jenkins, cluster-autoscaler, fluent-bit, external-secrets, karpenter) use Pod Identity associations — no node-level credentials shared.
- **Least-privilege IAM.** Each Terraform module owns its IAM role scoped to its resources.
- **NetworkPolicies.** `weather-api` accepts ingress only from `ingress-nginx`; egress only to DNS and Open-Meteo.
- **Public-subnet topology (POC trade-off).** Worker nodes have public IPs; no NAT Gateway. Inbound contained by SGs + API GW + Lambda authorizer. For production: private subnets + NAT or VPC endpoints.

## 7. Out of Scope

- Multi-region deployment (single `us-east-1`)
- WAF / DDoS protection (Shield Advanced)
- Custom DNS/TLS via Route53 + ACM
- GitOps continuous deployment (ArgoCD)
- Service mesh (Istio/Linkerd)
