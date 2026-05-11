#!/usr/bin/env bash
# collect-evidence.sh — KEDA smoke test evidence watcher
# Samples HPA/pod replica count every 15s for OBSERVE_SECONDS (default 1200).
# Emits timeline.log + timeline-summary.json + final snapshot files.
set -euo pipefail

OBSERVE_SECONDS="${OBSERVE_SECONDS:-1200}"
SAMPLE_INTERVAL=15
NAMESPACE="${NAMESPACE:-weather-staging}"
DEPLOY="${DEPLOY:-weather-api}"
HPA="${HPA:-keda-hpa-weather-api}"
OUTPUT_DIR="${OUTPUT_DIR:-docs/evidence/keda-smoke}"

usage() {
  echo "Usage: $0 [--help]"
  echo ""
  echo "Environment variables:"
  echo "  OBSERVE_SECONDS   Total observation window in seconds (default: 1200)"
  echo "  NAMESPACE         Kubernetes namespace (default: weather-staging)"
  echo "  DEPLOY            Deployment name (default: weather-api)"
  echo "  HPA               HPA name (default: keda-hpa-weather-api)"
  echo "  OUTPUT_DIR        Evidence output directory (default: docs/evidence/keda-smoke)"
  echo ""
  echo "Output files:"
  echo "  \$OUTPUT_DIR/timeline.log          — JSON-lines time-series of replica counts"
  echo "  \$OUTPUT_DIR/timeline-summary.json — Peak/final replicas + scale timing"
  echo "  \$OUTPUT_DIR/hpa-events.txt        — kubectl get events (end of observation)"
  echo "  \$OUTPUT_DIR/scaledobject-describe.txt — kubectl describe scaledobject"
  echo "  \$OUTPUT_DIR/k6-output.txt         — k6 job logs"
  exit 0
}

[[ "${1:-}" == "--help" ]] && usage

mkdir -p "$OUTPUT_DIR"

TIMELINE="$OUTPUT_DIR/timeline.log"
: > "$TIMELINE"

START_TS=$(date +%s)
SCALE_UP_TS=""
BASELINE_REPLICAS=""
PEAK_REPLICAS=0

echo "[collect-evidence] Starting observation: ${OBSERVE_SECONDS}s, sampling every ${SAMPLE_INTERVAL}s"
echo "[collect-evidence] Namespace: $NAMESPACE | Deploy: $DEPLOY | HPA: $HPA"

ELAPSED=0
while [[ $ELAPSED -lt $OBSERVE_SECONDS ]]; do
  NOW=$(date +%s)
  ELAPSED=$(( NOW - START_TS ))

  # Get current ready replicas
  READY=$(kubectl get deploy "$DEPLOY" -n "$NAMESPACE" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  READY="${READY:-0}"

  # Get HPA current/desired
  HPA_CURRENT=$(kubectl get hpa "$HPA" -n "$NAMESPACE" \
    -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo "0")
  HPA_DESIRED=$(kubectl get hpa "$HPA" -n "$NAMESPACE" \
    -o jsonpath='{.status.desiredReplicas}' 2>/dev/null || echo "0")

  # Capture baseline on first sample
  if [[ -z "$BASELINE_REPLICAS" ]]; then
    BASELINE_REPLICAS="$READY"
  fi

  # Track peak
  if [[ "$READY" -gt "$PEAK_REPLICAS" ]]; then
    PEAK_REPLICAS="$READY"
  fi

  # Detect first scale-up event
  if [[ -z "$SCALE_UP_TS" && "$READY" -gt "${BASELINE_REPLICAS:-2}" ]]; then
    SCALE_UP_TS="$ELAPSED"
  fi

  # Emit JSON-lines entry
  printf '{"ts":%d,"elapsed":%d,"ready_replicas":%s,"hpa_current":%s,"hpa_desired":%s}\n' \
    "$NOW" "$ELAPSED" "$READY" "${HPA_CURRENT:-0}" "${HPA_DESIRED:-0}" \
    >> "$TIMELINE"

  echo "[${ELAPSED}s] ready=${READY} hpa_current=${HPA_CURRENT:-0} hpa_desired=${HPA_DESIRED:-0}"

  sleep "$SAMPLE_INTERVAL"
done

echo "[collect-evidence] Observation complete. Capturing final state..."

# Final replica count
FINAL_REPLICAS=$(kubectl get deploy "$DEPLOY" -n "$NAMESPACE" \
  -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
FINAL_REPLICAS="${FINAL_REPLICAS:-0}"

# Scale-up seconds (null if never happened)
SCALE_UP_SECS="${SCALE_UP_TS:-null}"

# Compute scale-down: find last timestamp where replicas > baseline then returned to baseline
SCALE_DOWN_SECS=$(awk -F'[:,}]' -v baseline="${BASELINE_REPLICAS:-2}" '
  /ready_replicas/ {
    for (i=1;i<=NF;i++) {
      if ($i ~ /ready_replicas/) {
        val=$(i+1)+0
        if (above && val <= baseline) {
          split(prev_line, a, /[:,}]/)
          for (j=1;j<=length(a);j++) {
            if (a[j] ~ /elapsed/) { down_ts = a[j+1]+0 }
          }
          split($0, b, /[:,}]/)
          for (j=1;j<=length(b);j++) {
            if (b[j] ~ /elapsed/) { down_end = b[j+1]+0 }
          }
          found=1
        }
        if (val > baseline) above=1
      }
    }
    prev_line=$0
  }
  END { if (found) print down_end; else print "null" }
' "$TIMELINE")

# Capture snapshot files
kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp \
  > "$OUTPUT_DIR/hpa-events.txt" 2>&1 || true

kubectl describe scaledobject "$DEPLOY" -n "$NAMESPACE" \
  > "$OUTPUT_DIR/scaledobject-describe.txt" 2>&1 || true

kubectl logs "job/keda-smoke-load" -n "$NAMESPACE" --tail=-1 \
  > "$OUTPUT_DIR/k6-output.txt" 2>&1 || true

# Emit summary JSON
cat > "$OUTPUT_DIR/timeline-summary.json" <<EOF
{
  "peak_replicas": ${PEAK_REPLICAS},
  "final_replicas": ${FINAL_REPLICAS},
  "baseline_replicas": ${BASELINE_REPLICAS:-2},
  "scale_up_seconds": ${SCALE_UP_SECS},
  "scale_down_seconds": ${SCALE_DOWN_SECS},
  "observe_seconds": ${OBSERVE_SECONDS}
}
EOF

echo "[collect-evidence] Done. Summary:"
cat "$OUTPUT_DIR/timeline-summary.json"
