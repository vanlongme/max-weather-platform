#!/usr/bin/env bash
# Runs k6 load test against the weather API and captures HPA scaling evidence.
# Phases:
#   1. Capture HPA + pod state BEFORE
#   2. Start background watchers
#   3. Run k6 load test
#   4. Sleep 60s for HPA stabilization
#   5. Capture AFTER state and verdict
#   6. Capture CloudWatch evidence
set -euo pipefail

NAMESPACE="${NAMESPACE:-weather-staging}"
EVIDENCE_DIR="docs/evidence/08-loadtest"
CW_DIR="docs/evidence/04-cloudwatch"
CLUSTER="${CLUSTER:-max-weather}"
REGION="${REGION:-us-east-1}"

mkdir -p "$EVIDENCE_DIR" "$CW_DIR"

log() { echo "[$(date -u +%FT%TZ)] $*"; }

log "Phase 1: Capturing HPA state BEFORE load test"
kubectl get hpa -n "$NAMESPACE" -o yaml > "$EVIDENCE_DIR/hpa-before.yaml"
kubectl get pods -n "$NAMESPACE" -l app=weather-api --no-headers | wc -l > "$EVIDENCE_DIR/pods-before.txt"
log "Pods before: $(cat "$EVIDENCE_DIR/pods-before.txt")"

log "Phase 2: Starting background watchers"
kubectl get hpa -n "$NAMESPACE" -w --no-headers > "$EVIDENCE_DIR/hpa-watch.log" 2>&1 &
HPA_WATCHER_PID=$!
kubectl get pods -n "$NAMESPACE" -l app=weather-api -w --no-headers > "$EVIDENCE_DIR/pods-watch.log" 2>&1 &
POD_WATCHER_PID=$!

cleanup() {
  kill "$HPA_WATCHER_PID" "$POD_WATCHER_PID" 2>/dev/null || true
}
trap cleanup EXIT

log "Phase 3: Running k6 load test"
NLB_URL="${NLB_URL:-${INVOKE_URL:-}}"
if [[ -z "${K6_AUTH_TOKEN:-}" ]]; then
  log "K6_AUTH_TOKEN not set — fetching via make issue-token"
  K6_AUTH_TOKEN=$(make issue-token) || { log "ERROR: make issue-token failed"; exit 1; }
fi
k6 run \
  --summary-export="$EVIDENCE_DIR/k6-summary.json" \
  -e NLB_URL="$NLB_URL" \
  -e K6_AUTH_TOKEN="$K6_AUTH_TOKEN" \
  tests/load/weather-load.js \
  2>&1 | tee "$EVIDENCE_DIR/run.log"

log "Phase 4: Waiting 60s for HPA stabilization..."
sleep 60

log "Phase 5: Capturing HPA state AFTER load test"
kubectl get hpa -n "$NAMESPACE" -o yaml > "$EVIDENCE_DIR/hpa-after.yaml"
kubectl describe hpa weather-api -n "$NAMESPACE" > "$EVIDENCE_DIR/hpa-describe.txt" 2>/dev/null || true
kubectl get pods -n "$NAMESPACE" -l app=weather-api --no-headers | wc -l > "$EVIDENCE_DIR/pods-after.txt"
kubectl top pods -n "$NAMESPACE" > "$EVIDENCE_DIR/pods-top.txt" 2>/dev/null || true

log "Pods after: $(cat "$EVIDENCE_DIR/pods-after.txt")"

BEFORE=$(tr -d ' \n' < "$EVIDENCE_DIR/pods-before.txt")
AFTER=$(tr -d ' \n' < "$EVIDENCE_DIR/pods-after.txt")
if [[ "$AFTER" -gt "$BEFORE" ]]; then
  echo "PASS: HPA scaled from $BEFORE -> $AFTER pods" | tee "$EVIDENCE_DIR/scaling-verdict.txt"
else
  echo "NOTE: HPA did not scale organically ($BEFORE -> $AFTER pods). Run scripts/force-scale-demo.sh for forced demo." | tee "$EVIDENCE_DIR/scaling-verdict.txt"
fi

log "Phase 6: Capturing CloudWatch logs evidence"
aws logs tail "/aws/eks/${CLUSTER}/application" --since 10m --format short \
  > "$CW_DIR/eks-app-logs.txt" 2>/dev/null \
  || echo "No application logs yet" > "$CW_DIR/eks-app-logs.txt"
aws logs tail "/aws/eks/${CLUSTER}/cluster" --since 10m --format short \
  > "$CW_DIR/eks-control-plane-logs.txt" 2>/dev/null \
  || echo "No control plane logs" > "$CW_DIR/eks-control-plane-logs.txt"
aws logs tail "/aws/lambda/max-weather-authorizer" --since 10m --format short \
  > "$CW_DIR/lambda-authorizer-logs.txt" 2>/dev/null \
  || echo "No Lambda logs yet" > "$CW_DIR/lambda-authorizer-logs.txt"

START_TIME=$(date -u -d '15 min ago' +%FT%TZ 2>/dev/null || date -u -v-15M +%FT%TZ)
END_TIME=$(date -u +%FT%TZ)
aws cloudwatch get-metric-statistics \
  --namespace ContainerInsights \
  --metric-name pod_cpu_utilization \
  --dimensions Name=ClusterName,Value="${CLUSTER}" \
  --start-time "$START_TIME" --end-time "$END_TIME" \
  --period 60 --statistics Average \
  --region "$REGION" \
  > "$CW_DIR/eks-cpu-metric.json" 2>/dev/null \
  || echo '{"Datapoints":[]}' > "$CW_DIR/eks-cpu-metric.json"

log "Load test complete. Evidence in $EVIDENCE_DIR and $CW_DIR"
