# KEDA Smoke Test

Validates that the KEDA ScaledObject for `weather-api` in the `weather-staging` namespace
scales the deployment up under CPU load and back down after load stops.

## Prerequisites

- `kubectl` configured for the `poc-max-weather` EKS cluster
- KEDA and metrics-server deployed (`infra/envs/poc/eks-self-managed-addons/`)
- `weather-api` Deployment running in `weather-staging` with `minReplicaCount=2`
- ScaledObject `weather-api` reporting `READY=True` (creates `keda-hpa-weather-api`)
- Optional: `tests/keda/collect-evidence.sh` running in the background to capture HPA timeline

## How to run

1. (Optional) Start the evidence watcher in a background terminal:
   ```bash
   bash tests/keda/collect-evidence.sh &
   WATCHER_PID=$!
   ```

2. Apply the smoke test Job:
   ```bash
   kubectl apply -f tests/keda/keda-smoke-job.yaml
   ```

3. Watch scale-up (target ≥4 replicas within 300s):
   ```bash
   kubectl -n weather-staging get deploy weather-api --watch
   ```

4. Wait for Job completion and post-load scale-down:
   ```bash
   kubectl -n weather-staging wait --for=condition=complete \
     job/keda-smoke-load --timeout=720s
   # Then wait ~900s for scale-down (cooldownPeriod=300s + stabilization=300s)
   ```

5. Collect evidence (watcher captures to `docs/evidence/keda-smoke/`):
   ```bash
   wait $WATCHER_PID  # or kill after ~1200s
   ```

## Expected behavior

| Phase           | Duration            | Pod count |
|-----------------|---------------------|-----------|
| Baseline        | before Job          | 2         |
| Ramp-up         | 0–5 min into Job    | 2 → 4+    |
| Sustained load  | 5–8 min into Job    | 4+        |
| Scale-down      | 0–15 min after Job  | 4+ → 2    |

Backed by `k8s/base/scaledobject.yaml`:
- CPU 60% utilization trigger
- `pollingInterval=15s`, `cooldownPeriod=300s`
- scale-up: 2 pods / 60s; scale-down stabilization: 300s

## Pass criteria

- Pod count reaches **≥4** within **300s** of Job start
- Pod count returns to **2** within **900s** of Job completion
- Evidence files present in `docs/evidence/keda-smoke/`

## In-cluster URL

The k6 script targets:

```
http://weather-api.weather-staging.svc.cluster.local:8080
```

This bypasses API Gateway and the Lambda HS256 authorizer — no JWT is required
inside the cluster mesh. The Service exposes port 8080 (matches the container).

## Cleanup

```bash
kubectl delete -f tests/keda/keda-smoke-job.yaml
# Deletes both Job and ConfigMap (single manifest)
```

`ttlSecondsAfterFinished=3600` also auto-cleans the Job 1 hour after completion.

## Files

- `keda-smoke-job.yaml` — Kubernetes Job manifest (includes `ConfigMap` with k6 script)
- `collect-evidence.sh` — watcher script capturing HPA timeline + summary JSON (separate task)
