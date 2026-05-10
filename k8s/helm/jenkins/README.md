# Jenkins (Helm)

Replaces the deleted `infra/modules/jenkins` Terraform module that ran
Jenkins on a standalone EC2 instance. This Helm release installs Jenkins
**inside the EKS cluster** so it benefits from the same autoscaling,
logging, monitoring, and IAM (EKS Pod Identity) plumbing as the
application workloads.

## Chart

| Field | Value |
|------|-------|
| Repo | `https://charts.jenkins.io` |
| Chart | `jenkinsci/jenkins` |
| Version | _Latest at install time_ — `scripts/install-helm-addons.sh` runs `helm repo update` then queries the newest chart version. Pin by setting `JENKINS_CHART_VERSION=<x.y.z>` before invoking the script. |

## What this release creates

- `jenkins` namespace
- `jenkins` Deployment (1 controller pod) with persistent `gp3` PVC (8Gi)
- `jenkins` ClusterIP Service + Ingress (class `nginx`) — surfaced via the
  existing public NLB provisioned by the `nginx-ingress` release. No second
  LoadBalancer is created.
- `jenkins` ServiceAccount (no IAM annotation). The IAM role itself is
  managed by `infra/modules/iam` (output: `jenkins_role_arn`) and bound
  to the SA via an `aws_eks_pod_identity_association` created by
  `infra/modules/eks`. Trust principal is `pods.eks.amazonaws.com`.
- `jenkins-agent` ServiceAccount used by the Kubernetes plugin to launch
  per-build agent pods.

## Access

```bash
# Admin password
kubectl -n jenkins get secret jenkins \
  -o jsonpath='{.data.jenkins-admin-password}' | base64 -d; echo

# UI URL (NLB hostname)
kubectl -n ingress-nginx get svc nginx-ingress-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
# -> http://<nlb-hostname>/   (path /)
```

## POC Trade-offs

- **No TLS termination** — the public NLB serves HTTP only. Production
  would attach an ACM certificate and switch the NLB listener to TLS,
  or front Jenkins with a separate internal-only ingress.
- **Single replica** — `controller.replicas` is implicitly 1. Jenkins
  is not HA-friendly without external storage clustering; run in active/
  passive only.
- **Persistence on EBS gp3** — survives pod restarts but is single-AZ.
  Production would use EFS for cross-AZ failover or accept lost-job risk.

## Removal

```bash
helm -n jenkins uninstall jenkins
kubectl delete namespace jenkins
```
