# Load Test Evidence — Max Weather HPA Scaling

This directory contains evidence of Kubernetes Horizontal Pod Autoscaler (HPA) scaling
triggered by the k6 load test, satisfying the PDF assessment mandate:
"Terraform code with respect to CloudWatch services and scaling should be tested before submitting."

## Test Script

**File**: `tests/load/weather-load.js`

**Load profile**:

| Stage | Duration | VUs |
|-------|----------|-----|
| Ramp up | 30s | 0 -> 10 |
| Sustain | 60s | 10 |
| Peak ramp | 60s | 10 -> 50 |
| Sustain peak | 120s | 50 |
| Cool down | 30s | 50 -> 0 |

**Thresholds**:
- p(95) response time < 2000ms
- Error rate < 5%
- Check pass rate > 95%

## HPA Configuration

The HPA (defined in `k8s/base/hpa.yaml`) targets 70% CPU utilization:
- Min replicas: 2
- Max replicas: 10

**Expected scaling**: When 50 VUs hit two Open-Meteo proxy requests/second per pod,
CPU should exceed 70%, triggering HPA to scale from 2 -> 4-5 pods within 1-2 minutes.

**Note on Open-Meteo caching**: If Open-Meteo returns cached responses, the pod CPU
may stay low. In this case, use `scripts/force-scale-demo.sh` to manually demonstrate
the scaling path (kubectl scale -> ReplicaSet -> new Pods -> Ready).

## Evidence Files

| File | Description |
|------|-------------|
| `hpa-before.yaml` | HPA state before load test (baseline replicas) |
| `hpa-after.yaml` | HPA state after load test |
| `hpa-describe.txt` | `kubectl describe hpa` output showing scaling events |
| `hpa-watch.log` | Live HPA watch output (timestamped events) |
| `pods-before.txt` | Pod count before |
| `pods-after.txt` | Pod count after |
| `pods-watch.log` | Live pod watch (shows pod creation events) |
| `pods-top.txt` | `kubectl top pods` CPU/memory during test |
| `k6-summary.json` | k6 metrics summary (exported JSON) |
| `run.log` | Full k6 run output |
| `scaling-verdict.txt` | PASS/NOTE verdict on whether organic scaling occurred |

## How to Run

```bash
# Set environment variables
export NLB_URL="http://<nlb-dns-name>"
export COGNITO_CLIENT_ID="<your-client-id>"
export COGNITO_CLIENT_SECRET="<your-client-secret>"
export COGNITO_TOKEN_ENDPOINT="https://<domain>.auth.us-east-1.amazoncognito.com/oauth2/token"

# Run full load test with evidence capture
make load-test

# OR force-scale demo (if organic scaling didn't trigger)
bash scripts/force-scale-demo.sh
```

## Interpreting Results

1. Check `scaling-verdict.txt` — PASS = organic HPA scaling occurred
2. Compare `pods-before.txt` vs `pods-after.txt` — shows replica delta
3. Review `hpa-describe.txt` `Events:` section — shows `SuccessfulRescale` events
4. Check `k6-summary.json` — `http_req_failed.values.rate` should be < 0.05

## CloudWatch Integration

See `docs/evidence/04-cloudwatch/` for:
- `eks-app-logs.txt` — Fluent Bit shipped application logs
- `eks-control-plane-logs.txt` — EKS control plane events
- `lambda-authorizer-logs.txt` — Lambda invocation logs
- `eks-cpu-metric.json` — Container Insights CPU metric data
