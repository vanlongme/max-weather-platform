# Architecture Reference

## 1. Overview

Max Weather is a containerized Node.js weather API on AWS EKS, fronted by an API Gateway HTTP API with a Lambda HS256 JWT authorizer. Two workload environments (`weather-staging`, `weather-prod`) live in the same cluster, separated by namespace + Kustomize overlay. Cluster addons (ingress-nginx, KEDA, Karpenter, Fluent Bit, External Secrets, Jenkins, metrics-server, cluster-autoscaler) are Terraform-managed via the Helm provider in `infra/envs/poc/eks-self-managed-addons/`. CI/CD runs in-cluster (Jenkins controller-only + pod-per-build agents). See the [architecture diagram](docs/architecture.png).

## 2. Data Plane Flow

1. **Client** issues an HS256 JWT via `bash scripts/issue-token.sh --env staging` (or `--env prod`). The script reads the per-env shared secret from Secrets Manager and signs locally — no network round-trip to mint.
2. **Client → API GW HTTP API** — `Authorization: Bearer <token>` header on `GET /weather`. Each env has its own API GW stage (`staging`, `prod`) with its own invoke URL.
3. **API GW → Lambda Authorizer** — verifies HS256 signature + `scope: weather-api/read`; returns `{isAuthorized: true|false}`. `/healthz` is configured with `AuthorizationType=NONE` (unauthenticated for ALB / smoke checks).
4. **API GW → VPC Link → NLB (internal)** — HTTP proxy integration over a private VPC link.
5. **NLB → ingress-nginx → weather-api** — L7 routing by Host header (`staging.max-weather.local` / `prod.max-weather.local`) inside the EKS cluster, terminating at the namespace-scoped Service.
6. **weather-api → Open-Meteo** — outbound HTTPS to the upstream weather API; JSON response returned to the client.

## 3. Components

| Component | Type | Location | Purpose |
|-----------|------|----------|---------|
| EKS Cluster | AWS managed K8s | `infra/modules/eks/` | Container orchestration |
| API Gateway HTTP API | AWS managed | `infra/modules/api_gateway/` | Public entry point + auth gateway (per-env stage) |
| Lambda Authorizer | AWS Lambda (Node.js 22) | `infra/envs/poc/lambdas/authorizer/` | HS256 JWT verification (per-env deployment) |
| NLB (internal) | AWS NLB | Created by ingress-nginx Service | Routes API GW → EKS |
| ingress-nginx | Helm release | `eks-self-managed-addons/values/ingress-nginx.yaml` | L7 routing inside EKS |
| KEDA ScaledObject | CRD (keda.sh/v1alpha1) | `k8s/base/scaledobject.yaml` | CPU-based pod autoscaling (Utilization=60) |
| Karpenter | Helm release + CRDs | `eks-self-managed-addons/values/karpenter.yaml` | Workload node provisioning |
| Cluster Autoscaler | Helm release | `eks-self-managed-addons/values/cluster-autoscaler.yaml` | System MNG autoscaling |
| Fluent Bit | Helm release | `eks-self-managed-addons/values/fluent-bit.yaml` | Log shipping to CloudWatch |
| External Secrets | Helm release | `eks-self-managed-addons/values/external-secrets.yaml` | Secrets Manager → K8s Secrets |
| metrics-server | Helm release | `eks-self-managed-addons/values/metrics-server.yaml` | CPU/memory metrics for KEDA |
| Jenkins | Helm release | `eks-self-managed-addons/values/jenkins.yaml` | CI/CD server in-cluster (JCasC + Job DSL seed) |
| Secrets Manager | AWS | Terraform-created | Per-env JWT shared secret + app config |
| ECR | AWS | `infra/modules/ecr/` | Container image registry (`poc-max-weather-api-repo`) |
| CloudWatch | AWS | `infra/modules/cloudwatch/` | Logs + Container Insights |
| aws-ebs-csi-driver | EKS add-on (Pod Identity) | `infra/envs/poc/main.tf` `local.csi_cluster_addons` | Block storage; `defaultStorageClass.enabled=true` creates `ebs-csi-default-sc` (gp3, default) |
| aws-efs-csi-driver | EKS add-on (Pod Identity) | `infra/envs/poc/main.tf` `local.csi_cluster_addons` | NFS driver + IAM role installed for ad-hoc EFS mounts (no FS provisioned by this repo) |

## 4. Workload Deployment Topology

| Env | Namespace | Min replicas | Max replicas | Ingress host | Image source |
|-----|-----------|--------------|--------------|--------------|--------------|
| staging | `weather-staging` | 2 | 10 | `staging.max-weather.local` | `<account>.dkr.ecr.us-east-1.amazonaws.com/poc-max-weather-api-repo:<git-sha>` |
| prod | `weather-prod` | 3 | 10 | `prod.max-weather.local` | same repo, same `<git-sha>` (promoted) |

Both envs share one ECR repo and one image per commit — the **same `$GIT_SHA`-tagged image** that passed staging is promoted to prod. No `latest` tag, no env-prefixed tags. Replica bounds and ingress host are the only deltas between overlays (`k8s/overlays/prod/{scaledobject,ingress,deployment-replicas}-patch.yaml`).

## 5. CI/CD Flow

```
main push  →  max-weather-ci (Jenkins, upstream)
                ├── Lint + Test (Jest)            ───→ JUnit published
                ├── Trivy scan (fails HIGH/CRIT)
                ├── kaniko build + push           ───→ ECR :<git-sha>
                ├── build job: max-weather-deploy (ENV=staging)
                │     └── kustomize edit set image  →  kubectl apply -k overlays/staging
                │         smoke test → auto-rollback on failure
                ├── input "Approve Prod Deploy"   (24h timeout)
                └── build job: max-weather-deploy (ENV=prod)
                      └── same flow, NO auto-rollback
```

- Jenkins controller runs in-cluster (no static agents); each build spawns a pod-per-build agent (kaniko, kustomize) via the Kubernetes plugin.
- Agent ServiceAccount holds an EKS access entry granting Edit on `weather-{staging,prod}` + ECR push — all via Pod Identity, zero static credentials.
- Pipelines are code: `jenkins/jobs.groovy` (Job DSL seed) + `jenkins/pipelines/*.Jenkinsfile`. Detailed flow in [`jenkins/README.md`](jenkins/README.md).

## 6. Scaling

**Pod scaling (KEDA):** `k8s/base/scaledobject.yaml` defines a `ScaledObject` with `type: cpu`, `metricType: Utilization`, `value: "60"`. KEDA generates a managed HPA (`keda-hpa-weather-api`) that scales weather-api pods between `minReplicaCount: 2` (staging) / `3` (prod) and `maxReplicaCount: 10`. Scale-up: 0s stabilization, +2 pods/60s. Scale-down: 300s stabilization. `pollingInterval: 15s`, `cooldownPeriod: 300s`. Verified by [`tests/keda/`](tests/keda/) smoke test.

**Node scaling (Karpenter):** Provisions on-demand `t3.medium`/`large` EC2 nodes (AL2023) via `NodePool` / `EC2NodeClass` CRDs applied by Terraform (`kubernetes_manifest`). Faster than Cluster Autoscaler (~30s vs ~3min). Handles workload pod bursts. Pods tolerate the `karpenter.sh/provisioned=true:NoSchedule` taint so only workload pods land on these nodes.

**System node scaling (Cluster Autoscaler):** Manages the static `general` Bottlerocket MNG (min 1, max 10 `t3.medium` init workers). Hosts kube-system pods including Karpenter's own controller, the Jenkins controller, and other addons.

## 7. Testing

| Suite | Where | Drives |
|-------|-------|--------|
| Unit (Jest + supertest) | `app/` | Express handlers, JWT helper, error paths |
| KEDA smoke | `tests/keda/` | Apply a k6 CPU-load Job, watch `keda-hpa-weather-api` scale 2→4+ and back to 2 |
| k6 load | `tests/load/weather-load.js` | Sustained ingress load against in-cluster service for KEDA/Karpenter exercise |
| API collection | `docs/postman/` | Postman collection + per-env environment templates; CLI via `newman run` |

Run unit tests in CI via `make test`. KEDA + k6 are operator-driven against a live cluster — entry points and pass criteria in [`tests/keda/README.md`](tests/keda/README.md).

## 8. Cost Estimate

Steady-state monthly (us-east-1, on-demand, idle load — 0 Karpenter-provisioned nodes):

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
| **Total (idle)** | **~139** |

Under sustained load, Karpenter adds workload nodes (~$30/mo per `t3.medium`) on demand and reaps them after the scale-down window. 2-day demo cost ≈ $12. Run `make teardown` immediately after evaluation — single-shot cloud-nuke wipe brings the account back to $0.

## 9. Security Posture

- **No secrets in Git.** Per-env JWT shared secret + app config in Secrets Manager, synced to K8s via External Secrets Operator. Postman env templates ship with the secret fields empty.
- **EKS Pod Identity (no IRSA).** All workloads (jenkins, jenkins-agent, weather-api, cluster-autoscaler, fluent-bit, external-secrets, karpenter, ebs-csi-controller, efs-csi-controller) use Pod Identity associations — no node-level credentials shared.
- **Least-privilege IAM.** Each Terraform module owns its IAM role scoped to its resources. Jenkins agent has EKS access entry granting Edit on `weather-{staging,prod}` only.
- **Container hardening.** `runAsNonRoot`, `readOnlyRootFilesystem`, `drop: [ALL]`, `allowPrivilegeEscalation: false`. Trivy scan in CI fails on HIGH/CRITICAL.
- **NetworkPolicies.** `weather-{staging,prod}` namespaces apply `deny-all-ingress` + `allow-from-ingress-nginx`. Egress open (Open-Meteo, AWS APIs).
- **Topology spread.** Pods spread across AZs (`maxSkew: 1`, `ScheduleAnyway`) — single-AZ event preserves quorum during KEDA scale-up.
- **Public-subnet topology (POC trade-off).** Worker nodes have public IPs; no NAT Gateway. Inbound contained by SGs + API GW + Lambda authorizer. EKS API endpoint public-access CIDRs validated to reject `0.0.0.0/0`. **For production**: private subnets + NAT or VPC endpoints.

## 10. Out of Scope

- Multi-region deployment (single `us-east-1`)
- WAF / DDoS protection (Shield Advanced)
- Custom DNS / TLS via Route53 + ACM (uses `*.max-weather.local` Host header today)
- GitOps continuous deployment (ArgoCD / Flux)
- Service mesh (Istio / Linkerd)
- Asymmetric JWT (RS256/ES256 via JWKS) — current HS256 is shared-secret only
