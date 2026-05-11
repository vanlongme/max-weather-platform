# Kubernetes Workload Manifests

Kustomize manifests for the `weather-api` workload. One `base/`, two overlays
(`staging`, `prod`). Cluster add-ons (KEDA, ingress-nginx, ExternalSecrets,
Karpenter, Jenkins, …) are **not** here — they live as Terraform `helm_release`s
under [`infra/envs/poc/eks-self-managed-addons/`](../infra/envs/poc/eks-self-managed-addons/).

---

## Layout

```
k8s/
├── base/                          # All env-agnostic workload resources
│   ├── deployment.yaml            # weather-api Deployment (port 8080, non-root, RO rootfs)
│   ├── service.yaml               # ClusterIP :8080
│   ├── ingress.yaml               # ingress-nginx host-based routing
│   ├── scaledobject.yaml          # KEDA CPU 60% util, min=2 max=10, polling=15s
│   ├── pdb.yaml                   # PodDisruptionBudget
│   ├── externalsecret.yaml        # External Secrets — pulls weather-app-config from Secrets Manager
│   ├── serviceaccount.yaml        # ServiceAccount bound via EKS Pod Identity (no IRSA annotation)
│   └── kustomization.yaml
├── overlays/
│   ├── staging/                   # namespace=weather-staging, image tag, ExternalSecret + SA patches
│   │   ├── namespace.yaml
│   │   └── kustomization.yaml
│   └── prod/                      # namespace=weather-prod, replica/scaledobject/ingress patches
│       ├── namespace.yaml
│       ├── deployment-replicas-patch.yaml
│       ├── scaledobject-patch.yaml
│       ├── ingress-patch.yaml
│       ├── externalsecret-patch.yaml
│       ├── serviceaccount-patch.yaml
│       └── kustomization.yaml
└── manifests/
    └── namespaces.yaml            # Namespaces + ResourceQuota + LimitRange + default-deny NetworkPolicy
```

---

## Deploy

Jenkins `max-weather-deploy` is the canonical entry point. Manual escape hatch:

```bash
make deploy-staging     # kubectl apply -k k8s/overlays/staging  +  rollout status (180s)
make deploy-prod        # kubectl apply -k k8s/overlays/prod
```

Cluster-wide bootstrap (namespaces, quotas, NetworkPolicies) is applied separately:

```bash
kubectl apply -f k8s/manifests/namespaces.yaml
```

---

## Image Tag Flow

Each overlay pins the image in its `kustomization.yaml`:

```yaml
images:
  - name: weather-api
    newName: <account>.dkr.ecr.us-east-1.amazonaws.com/poc-max-weather-api-repo
    newTag: <git-sha>
```

Jenkins `max-weather-deploy` updates `newTag` at deploy time:

```bash
cd k8s/overlays/<env>
kustomize edit set image weather-api=<newName>:<IMAGE_TAG>
kubectl apply -k .
```

Only one image tag exists per build: the short `$GIT_SHA`. No `:latest`, no env prefixes.

---

## Conventions

- **Namespaces**: `weather-staging`, `weather-prod` — set by each overlay's `namespace:` field. The base manifests use `weather-staging` as a literal default; the kustomize namespace transformer overwrites it in prod.
- **KEDA ScaledObject**: CPU 60% utilization, `min=2 max=10`, `pollingInterval=15s`, `cooldownPeriod=300s`. Scale-up policy: 2 pods / 60s. Scale-down stabilization: 300s. Prod overlay patches replica bounds via `scaledobject-patch.yaml`.
- **ExternalSecret**: `weather-app-config` is pulled from AWS Secrets Manager by External Secrets Operator and mounted as `envFrom: secretRef`. **NEVER** embed literal secret values in YAML.
- **ServiceAccount**: `weather-api` SA is bound to its IAM role via EKS **Pod Identity** — no `eks.amazonaws.com/role-arn` annotation (that's the legacy IRSA pattern).
- **Pod hardening**: `runAsNonRoot: true`, `runAsUser: 1000`, `readOnlyRootFilesystem: true`, drops all caps, `allowPrivilegeEscalation: false`.
- **Topology spread**: pods spread across AZs (`maxSkew: 1`, `ScheduleAnyway`) so KEDA scale-up survives a single-AZ event.
- **Karpenter tolerance**: pods tolerate the `karpenter.sh/provisioned=true:NoSchedule` taint so Karpenter-provisioned workload nodes can host them.
- **NetworkPolicies**: namespace bootstrap installs `deny-all-ingress` + `allow-from-ingress-nginx`. Egress is open (pods need Open-Meteo / AWS APIs).

---

## What's NOT in here

Anything owned by a Helm chart belongs in `infra/envs/poc/eks-self-managed-addons/values/<chart>.yaml`, not in a sibling K8s manifest:

| Concern | Where it actually lives |
|---------|-------------------------|
| Jenkins controller + JCasC + seed job | `infra/envs/poc/eks-self-managed-addons/values/jenkins.yaml` |
| ingress-nginx Service (NLB) | `values/ingress-nginx.yaml` |
| KEDA / ExternalSecrets / Karpenter / metrics-server / fluent-bit / cluster-autoscaler | corresponding `values/*.yaml` |
| Karpenter `NodePool` + `EC2NodeClass` CRDs | `values/karpenter-nodepool.yaml`, `values/karpenter-ec2nodeclass.yaml` (applied as `kubernetes_manifest`) |
| ECR repos / IAM / Secrets / VPC | `infra/envs/poc/main.tf` + `infra/modules/*` |

---

## Anti-Patterns

- **NEVER** use `imagePullSecrets` — ECR pull is handled by Pod Identity / node IAM.
- **NEVER** scale the Deployment with `kubectl scale` — KEDA HPA overrides on the next 15s poll.
- **NEVER** add a separate `HorizontalPodAutoscaler` — KEDA's ScaledObject owns the HPA lifecycle (creates `keda-hpa-weather-api`).
- **NEVER** edit `keda-hpa-*` directly — managed by the KEDA controller; edit `scaledobject.yaml` instead.
- **NEVER** commit literal secret values — `ExternalSecret` resolves them at runtime only.
- **NEVER** create standalone manifests for resources a Helm chart already owns — tune via the chart's `values/<chart>.yaml`.

---

## Cross-links

- [`base/scaledobject.yaml`](base/scaledobject.yaml) — KEDA scaling policy
- [`infra/envs/poc/eks-self-managed-addons/`](../infra/envs/poc/eks-self-managed-addons/) — Cluster add-ons (Terraform-managed Helm releases)
- [`jenkins/README.md`](../jenkins/README.md) — Pipeline that drives `kubectl apply -k`
- [`tests/keda/README.md`](../tests/keda/README.md) — KEDA scale smoke test against this Deployment
- [`Makefile`](../Makefile) `deploy-staging` / `deploy-prod` — manual deploy entry points
