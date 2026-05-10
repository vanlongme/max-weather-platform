#!/usr/bin/env bash
# Verifies that all expected evidence files are present and non-empty.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
PASS=0
FAIL=0

check() {
  local path="$1"
  if [[ -s "$path" ]]; then
    echo -e "${GREEN}PASS${NC} $path"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${NC} $path (missing or empty)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Evidence Verification ==="

# D1 Diagram
check "docs/architecture.drawio"
check "docs/architecture.png"

# D2 Terraform
check "infra/envs/poc/main.tf"
check "infra/bootstrap/main.tf"

# D3 K8s
check "k8s/base/kustomization.yaml"
check "k8s/overlays/staging/kustomization.yaml"

# D4 Jenkins
check "app/Jenkinsfile"
check "app/README.md"

# D5 API Gateway
check "docs/api-gateway-runbook.md"

# D6 Postman
check "docs/postman/max-weather.postman_collection.json"
check "docs/postman/staging.postman_environment.json"

# Evidence files (best-effort — collected post-deployment)
for f in \
  "docs/evidence/01-terraform/validate.txt" \
  "docs/evidence/02-eks/nodes.txt" \
  "docs/evidence/03-k8s/deploy-describe.txt" \
  "docs/evidence/08-loadtest/k6-summary.json" \
  "docs/evidence/08-loadtest/hpa-before.yaml" \
  "docs/evidence/08-loadtest/scaling-verdict.txt" \
  "docs/evidence/04-cloudwatch/eks-app-logs.txt"; do
  check "$f"
done

echo ""
echo "=== Summary: ${PASS} PASS | ${FAIL} FAIL ==="
if [[ $FAIL -gt 0 ]]; then
  echo "Some evidence files missing. Run 'make evidence' (and 'make load-test') to collect."
  exit 1
fi
echo "All evidence present."
