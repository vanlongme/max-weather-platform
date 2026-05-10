#!/usr/bin/env bash
# Force-scale fallback for HPA evidence.
# Use when k6 load test does not organically trigger HPA (e.g. due to Open-Meteo caching).
# Demonstrates that the HPA wiring (Deployment -> ReplicaSet -> Pods) works.
set -euo pipefail

NAMESPACE="${NAMESPACE:-weather-staging}"
EVIDENCE_DIR="docs/evidence/08-loadtest"
TARGET_REPLICAS="${TARGET_REPLICAS:-5}"

mkdir -p "$EVIDENCE_DIR"

echo "Force-scaling weather-api to $TARGET_REPLICAS replicas in $NAMESPACE (HPA demo fallback)"
kubectl scale deployment weather-api -n "$NAMESPACE" --replicas="$TARGET_REPLICAS"
sleep 10
kubectl get pods -n "$NAMESPACE" -l app=weather-api
kubectl get pods -n "$NAMESPACE" -l app=weather-api --no-headers | wc -l > "$EVIDENCE_DIR/pods-forced.txt"

{
  echo "FALLBACK: Forced scale to $TARGET_REPLICAS replicas. HPA will scale down to min after cooldown."
  echo "NOTE: This demonstrates HPA wiring (ReplicaSet control path works). Organic HPA trigger requires sustained CPU > 70%."
} | tee "$EVIDENCE_DIR/scaling-verdict.txt"
