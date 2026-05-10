#!/usr/bin/env bash
# Full ordered teardown of Max Weather infrastructure.
# 9 phases: confirmation, app, LB wait, helm, namespaces, manual API GW,
#           terraform destroy, bootstrap (optional), cloud-nuke verify, report.
set -euo pipefail

REGION="${REGION:-us-east-1}"
CLUSTER="${CLUSTER:-max-weather}"
NAMESPACE_STAGING="weather-staging"
NAMESPACE_PROD="weather-prod"
STAGING_DIR="${STAGING_DIR:-infra/envs/staging}"
START_TIME=$(date +%s)

log()  { echo "[$(date -u +%FT%TZ)] [INFO]  $*"; }
warn() { echo "[$(date -u +%FT%TZ)] [WARN]  $*"; }
err()  { echo "[$(date -u +%FT%TZ)] [ERROR] $*" >&2; }

mkdir -p docs/evidence/09-teardown

# Phase 0: Confirmation
echo ""
echo "============================================================"
echo "       MAX WEATHER - FULL INFRASTRUCTURE TEARDOWN          "
echo "============================================================"
echo ""
echo "This will destroy ALL max-weather infrastructure including:"
echo "  - EKS cluster and all workloads"
echo "  - VPC, subnets, NAT Gateway, NLB"
echo "  - ECR repositories and images"
echo "  - Cognito User Pool and clients"
echo "  - Lambda authorizer"
echo "  - Jenkins EC2 instance"
echo "  - CloudWatch log groups"
echo "  - Secrets Manager secrets"
echo ""
warn "THIS IS IRREVERSIBLE. Estimated cost savings: ~\$215/month."
echo ""
read -rp "Type 'destroy max-weather' to confirm: " CONFIRM
if [[ "$CONFIRM" != "destroy max-weather" ]]; then
  err "Confirmation failed. Aborting teardown."
  exit 1
fi

log "Confirmation received. Starting teardown..."

# Phase 1: Application Layer
log "Phase 1: Removing application workloads (triggers LB cleanup)"
if kubectl config current-context &>/dev/null; then
  kubectl delete -k k8s/overlays/staging --ignore-not-found || warn "Staging delete had errors (continuing)"
  kubectl delete -k k8s/overlays/prod --ignore-not-found 2>/dev/null || true
else
  warn "kubectl not connected to cluster - skipping Phase 1 (Terraform destroy will handle)"
fi

# Phase 2: Wait for LB cleanup
log "Phase 2: Waiting 60s for AWS Load Balancer Controller to clean up target groups..."
sleep 60
LB_CHECK=$(aws elbv2 describe-load-balancers --region "$REGION" \
  --query "LoadBalancers[?contains(LoadBalancerName,'max-weather')].LoadBalancerArn" \
  --output text 2>/dev/null || true)
if [[ -n "$LB_CHECK" ]]; then
  warn "Load Balancers still present: $LB_CHECK - waiting extra 60s"
  sleep 60
fi

# Phase 3: Helm Releases
log "Phase 3: Uninstalling Helm releases"
HELM_RELEASES=(
  "ingress-nginx:ingress-nginx"
  "aws-load-balancer-controller:kube-system"
  "cluster-autoscaler:kube-system"
  "fluent-bit:amazon-cloudwatch"
  "external-secrets:external-secrets"
  "metrics-server:kube-system"
)
if kubectl config current-context &>/dev/null; then
  for entry in "${HELM_RELEASES[@]}"; do
    release="${entry%%:*}"
    ns="${entry##*:}"
    helm uninstall "$release" -n "$ns" 2>/dev/null || warn "helm uninstall $release skipped (not found)"
  done
fi

# Phase 4: Namespaces
log "Phase 4: Deleting Kubernetes namespaces"
if kubectl config current-context &>/dev/null; then
  kubectl delete ns \
    "$NAMESPACE_STAGING" "$NAMESPACE_PROD" \
    ingress-nginx amazon-cloudwatch external-secrets \
    --ignore-not-found --timeout=120s 2>/dev/null || warn "Namespace deletion had issues"
fi

# Phase 5: Manual API Gateway
log "Phase 5: Manual API Gateway deletion required"
echo ""
echo "  +-------------------------------------------------------+"
echo "  | ACTION REQUIRED: Delete API Gateway manually          |"
echo "  |                                                       |"
echo "  | 1. Open: https://console.aws.amazon.com/apigateway    |"
echo "  | 2. Navigate to 'APIs'                                 |"
echo "  | 3. Find 'max-weather-api' and delete it               |"
echo "  | 4. Also delete the Lambda authorizer if shown         |"
echo "  +-------------------------------------------------------+"
echo ""
read -rp "Press ENTER when API Gateway is deleted (or type 'skip' to continue): " AGW_CONFIRM
if [[ "$AGW_CONFIRM" == "skip" ]]; then
  warn "Skipping API Gateway deletion - remember to delete manually"
fi

# Phase 6: Terraform Destroy
log "Phase 6: Running terraform destroy for staging environment"
(cd "$STAGING_DIR" && terraform init -reconfigure -input=false) || warn "Terraform init failed"
(cd "$STAGING_DIR" && terraform destroy -auto-approve \
  2>&1 | tee ../../docs/evidence/09-teardown/terraform-destroy.log) \
  || warn "Terraform destroy had errors - check docs/evidence/09-teardown/terraform-destroy.log"

# Phase 7: Bootstrap (Optional)
log "Phase 7: Bootstrap teardown (optional)"
echo ""
echo "  To also delete the Terraform state S3 bucket and DynamoDB table:"
echo "    cd infra/bootstrap && terraform destroy -auto-approve"
echo ""
echo "  WARNING: Only do this if you are sure no other state files use this backend."

# Phase 8: Cloud-Nuke Verification
log "Phase 8: Running cloud-nuke dry-run to check for orphaned resources"
if [[ -x "./cloud-nuke_linux_amd64" ]]; then
  ./cloud-nuke_linux_amd64 aws --region "$REGION" --config .cloud-nuke.yaml --dry-run \
    2>&1 | tee docs/evidence/09-teardown/cloud-nuke-dry.log || true
  ORPHAN_COUNT=$(grep -c "Would nuke" docs/evidence/09-teardown/cloud-nuke-dry.log 2>/dev/null || echo "0")
  if [[ "$ORPHAN_COUNT" -gt 0 ]]; then
    warn "$ORPHAN_COUNT orphaned resources found. Run 'make cloud-nuke-force' to clean up."
  else
    log "No orphaned resources found."
  fi
else
  warn "cloud-nuke_linux_amd64 binary not found - skipping orphan check"
fi

# Phase 9: Final Report
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

echo ""
echo "============================================================"
echo "                  TEARDOWN COMPLETE                         "
echo "============================================================"
log "Total elapsed: ${ELAPSED}s (~$((ELAPSED/60)) minutes)"
log "Estimated monthly savings: ~\$215/month"
log "Evidence saved to: docs/evidence/09-teardown/"
echo ""
echo "Post-teardown verification:"
echo "  aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=max-weather \\"
echo "    --region $REGION --query 'ResourceTagMappingList[].ResourceARN' --output text"
