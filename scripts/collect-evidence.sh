#!/usr/bin/env bash
# Collects all evidence artifacts. Read-only — does not modify infrastructure.
set -euo pipefail

CLUSTER="${CLUSTER:-max-weather}"
REGION="${REGION:-us-east-1}"
NAMESPACE="${NAMESPACE:-weather-staging}"
STAGING_DIR="${STAGING_DIR:-infra/envs/poc}"

log() { echo "[$(date -u +%FT%TZ)] $*"; }
EVIDENCE_BASE="docs/evidence"

mkdir -p \
  "$EVIDENCE_BASE/01-terraform" \
  "$EVIDENCE_BASE/02-eks" \
  "$EVIDENCE_BASE/03-k8s" \
  "$EVIDENCE_BASE/04-cloudwatch" \
  "$EVIDENCE_BASE/05-app" \
  "$EVIDENCE_BASE/06-lambda" \
  "$EVIDENCE_BASE/07-jenkins" \
  "$EVIDENCE_BASE/08-loadtest" \
  "$EVIDENCE_BASE/09-teardown"

log "01: Terraform evidence"
(cd "$STAGING_DIR" && terraform validate -no-color) > "$EVIDENCE_BASE/01-terraform/validate.txt" 2>&1 || true
terraform fmt -check -recursive infra/ > "$EVIDENCE_BASE/01-terraform/fmt-check.txt" 2>&1 || true
(cd "$STAGING_DIR" && terraform state list 2>/dev/null) \
  > "$EVIDENCE_BASE/01-terraform/state-list.txt" \
  || echo "(state not initialized)" > "$EVIDENCE_BASE/01-terraform/state-list.txt"
(cd "$STAGING_DIR" && terraform output -json 2>/dev/null | bash scripts/sanitize-outputs.sh) \
  > "$EVIDENCE_BASE/01-terraform/outputs.json" \
  || echo '{}' > "$EVIDENCE_BASE/01-terraform/outputs.json"

log "02: EKS evidence"
kubectl get nodes -o wide > "$EVIDENCE_BASE/02-eks/nodes.txt" 2>/dev/null \
  || echo "(not connected)" > "$EVIDENCE_BASE/02-eks/nodes.txt"
kubectl get pods -A > "$EVIDENCE_BASE/02-eks/pods-all-ns.txt" 2>/dev/null || true
helm list -A > "$EVIDENCE_BASE/02-eks/helm-releases.txt" 2>/dev/null || true
kubectl get crds 2>/dev/null | grep -E "(externalsecret|ingress|targetgroupbinding)" \
  > "$EVIDENCE_BASE/02-eks/crds.txt" || true

log "03: K8s manifests evidence"
kubectl describe deploy weather-api -n "$NAMESPACE" \
  > "$EVIDENCE_BASE/03-k8s/deploy-describe.txt" 2>/dev/null || true
kubectl describe svc weather-api -n "$NAMESPACE" \
  > "$EVIDENCE_BASE/03-k8s/svc-describe.txt" 2>/dev/null || true
kubectl describe ingress weather-api -n "$NAMESPACE" \
  > "$EVIDENCE_BASE/03-k8s/ingress-describe.txt" 2>/dev/null || true
kubectl get networkpolicy -A > "$EVIDENCE_BASE/03-k8s/netpol.txt" 2>/dev/null || true
kubectl get resourcequota -A > "$EVIDENCE_BASE/03-k8s/resourcequota.txt" 2>/dev/null || true
kubectl get hpa -n "$NAMESPACE" -o yaml > "$EVIDENCE_BASE/03-k8s/hpa.yaml" 2>/dev/null || true

log "06: Lambda evidence"
aws lambda get-function-configuration \
  --function-name max-weather-authorizer \
  --region "$REGION" \
  > "$EVIDENCE_BASE/06-lambda/config.json" 2>/dev/null \
  || echo '{}' > "$EVIDENCE_BASE/06-lambda/config.json"

cat > "$EVIDENCE_BASE/06-lambda/test-event-allow.json" << 'EVTEOF'
{"type":"REQUEST","identitySource":"Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.EXAMPLE","routeKey":"GET /weather","rawPath":"/weather","requestContext":{"http":{"method":"GET"}}}
EVTEOF

cat > "$EVIDENCE_BASE/06-lambda/test-event-deny.json" << 'EVTEOF'
{"type":"REQUEST","identitySource":"Bearer invalid.token.here","routeKey":"GET /weather","rawPath":"/weather","requestContext":{"http":{"method":"GET"}}}
EVTEOF

log "Evidence collection complete. Run 'make verify-evidence' to check completeness."
