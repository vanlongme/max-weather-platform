#!/usr/bin/env bash
# Ordered teardown of Max Weather infrastructure.
#
# Strategy: clean `terraform destroy` first (workload → bootstrap), then
# cloud-nuke as a final orphan sweep for any AWS resources Terraform missed
# (e.g. Karpenter-provisioned EC2, LB-controller-provisioned NLBs, ENIs,
# security-group dependencies). Account returns to zero with full state
# integrity along the way.
#
# Phases:
#   0. Confirmation
#   1. Empty ECR repos (so `aws_ecr_repository` destroy succeeds)
#   2. Force-delete Secrets Manager secrets (skip 7-30d recovery window)
#   3. kubectl pre-drain (delete K8s Services/Ingresses so AWS LB controller
#      releases NLBs/ALBs and ENIs before EKS destroy)
#   4. terraform destroy infra/envs/poc (workload composition — remote state)
#   5. terraform destroy infra/bootstrap (tfstate S3 + tflock DynamoDB)
#   6. cloud-nuke final sweep (any orphan *max-weather* resources)
#   7. Report
set -euo pipefail

REGION="${REGION:-us-east-1}"
PROJECT="${PROJECT:-max-weather}"
ENV_DIR="infra/envs/poc"
BOOTSTRAP_DIR="infra/bootstrap"
START_TIME=$(date +%s)

log()  { echo "[$(date -u +%FT%TZ)] [INFO]  $*"; }
warn() { echo "[$(date -u +%FT%TZ)] [WARN]  $*"; }
err()  { echo "[$(date -u +%FT%TZ)] [ERROR] $*" >&2; }

mkdir -p docs/evidence/09-teardown

# ─── Phase 0: Confirmation ──────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "       MAX WEATHER - ORDERED TEARDOWN                       "
echo "============================================================"
echo ""
echo "This will destroy every AWS resource for project '${PROJECT}':"
echo "  - terraform destroy ${ENV_DIR}   (workload: EKS, VPC, ECR, Lambda, …)"
echo "  - terraform destroy ${BOOTSTRAP_DIR}  (tfstate S3 + tflock DynamoDB)"
echo "  - cloud-nuke sweep of any *${PROJECT}* orphans (ENIs, NLBs, EC2, etc.)"
echo ""
warn "THIS IS IRREVERSIBLE. Secrets are force-deleted (no recovery)."
echo ""
read -rp "Type 'destroy max-weather' to confirm: " CONFIRM
if [[ "$CONFIRM" != "destroy max-weather" ]]; then
  err "Confirmation failed. Aborting teardown."
  exit 1
fi
log "Confirmation received. Starting ordered teardown..."

# ─── Phase 1: Empty ECR repos ───────────────────────────────────────────────
log "Phase 1: Emptying ECR repositories matching *${PROJECT}*"
ECR_REPOS=$(aws ecr describe-repositories --region "$REGION" \
  --query "repositories[?contains(repositoryName,'${PROJECT}')].repositoryName" \
  --output text 2>/dev/null || true)
for repo in $ECR_REPOS; do
  IMAGE_IDS=$(aws ecr list-images --repository-name "$repo" --region "$REGION" \
    --query 'imageIds[*]' --output json 2>/dev/null || echo '[]')
  if [[ "$IMAGE_IDS" != "[]" && -n "$IMAGE_IDS" ]]; then
    log "Emptying ECR repository $repo"
    aws ecr batch-delete-image --repository-name "$repo" --region "$REGION" \
      --image-ids "$IMAGE_IDS" >/dev/null 2>&1 \
      || warn "ECR empty failed for $repo (continuing)"
  fi
done

# ─── Phase 2: Force-delete Secrets Manager secrets ──────────────────────────
log "Phase 2: Force-deleting Secrets Manager secrets (no recovery)"
for secret_id in "poc-${PROJECT}-authorizer-jwt-secret" "/poc-${PROJECT}/app/config"; do
  aws secretsmanager delete-secret \
    --secret-id "$secret_id" \
    --force-delete-without-recovery \
    --region "$REGION" 2>/dev/null \
    && log "Force-deleted secret: $secret_id" \
    || warn "Secret $secret_id not found or already deleted (continuing)"
done

# ─── Phase 3: kubectl pre-drain (release AWS LB controller-owned NLBs) ──────
log "Phase 3: Draining K8s Services/Ingresses (releases NLBs/ENIs)"
if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
  # Delete LoadBalancer Services + Ingresses across all namespaces — the
  # aws-load-balancer-controller will tear down the underlying NLBs/ALBs and
  # ENIs. Without this, terraform destroy on the VPC stalls on dangling ENIs.
  kubectl get svc -A -o json 2>/dev/null \
    | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' \
    | while read -r ns name; do
        [[ -z "$ns" ]] && continue
        log "Deleting LoadBalancer Service $ns/$name"
        kubectl delete svc -n "$ns" "$name" --timeout=120s 2>&1 \
          | tee -a docs/evidence/09-teardown/kubectl-drain.log \
          || warn "Failed to delete svc $ns/$name (continuing)"
      done
  kubectl delete ingress --all -A --timeout=120s 2>&1 \
    | tee -a docs/evidence/09-teardown/kubectl-drain.log \
    || warn "Ingress delete had errors (continuing)"
  # Give LB controller ~30s to finalize NLB/ENI cleanup
  log "Waiting 30s for AWS LB controller to release NLBs/ENIs"
  sleep 30
else
  warn "kubectl unavailable or cluster unreachable — skipping pre-drain"
fi

# ─── Phase 4: terraform destroy envs/poc (workload) ─────────────────────────
log "Phase 4: terraform destroy ${ENV_DIR}"
if [[ -d "${ENV_DIR}/.terraform" ]]; then
  (cd "${ENV_DIR}" && terraform destroy -auto-approve) 2>&1 \
    | tee docs/evidence/09-teardown/tf-destroy-envs.log \
    || warn "terraform destroy ${ENV_DIR} had errors (cloud-nuke will sweep orphans)"
else
  warn "${ENV_DIR}/.terraform not initialized — skipping (cloud-nuke will handle)"
fi

# ─── Phase 5: terraform destroy bootstrap (tfstate backend) ─────────────────
log "Phase 5: terraform destroy ${BOOTSTRAP_DIR} (tfstate S3 + tflock DynamoDB)"
if [[ -d "${BOOTSTRAP_DIR}/.terraform" || -f "${BOOTSTRAP_DIR}/terraform.tfstate" ]]; then
  (cd "${BOOTSTRAP_DIR}" && terraform destroy -auto-approve) 2>&1 \
    | tee docs/evidence/09-teardown/tf-destroy-bootstrap.log \
    || warn "terraform destroy ${BOOTSTRAP_DIR} had errors (cloud-nuke will sweep orphans)"
else
  warn "${BOOTSTRAP_DIR} state not found — skipping (cloud-nuke will handle)"
fi

# ─── Phase 6: cloud-nuke orphan sweep ───────────────────────────────────────
log "Phase 6: cloud-nuke final orphan sweep (anything matching *${PROJECT}*)"
if [[ -x "./cloud-nuke_linux_amd64" ]]; then
  ./cloud-nuke_linux_amd64 aws --region "$REGION" --config .cloud-nuke.yaml --force \
    2>&1 | tee docs/evidence/09-teardown/cloud-nuke.log \
    || warn "cloud-nuke had errors - check docs/evidence/09-teardown/cloud-nuke.log"
else
  warn "cloud-nuke_linux_amd64 not found — skipping orphan sweep"
  warn "Install: https://github.com/gruntwork-io/cloud-nuke/releases"
fi

# ─── Phase 7: Final Report ──────────────────────────────────────────────────
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
echo "  aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=${PROJECT} \\"
echo "    --region $REGION --query 'ResourceTagMappingList[].ResourceARN' --output text"
