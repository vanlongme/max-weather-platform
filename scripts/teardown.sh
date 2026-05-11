#!/usr/bin/env bash
# Force teardown of Max Weather infrastructure via cloud-nuke.
# Skips ordered kubectl/helm/terraform-destroy cleanup — cloud-nuke wipes
# every AWS resource matching `*max-weather*` (incl. tfstate S3 + tflock
# DynamoDB) in one sweep. ECR repos are emptied first (cloud-nuke cannot
# delete repos with images), and Secrets Manager secrets are force-deleted
# without recovery window to keep the account truly at zero.
set -euo pipefail

REGION="${REGION:-us-east-1}"
START_TIME=$(date +%s)

log()  { echo "[$(date -u +%FT%TZ)] [INFO]  $*"; }
warn() { echo "[$(date -u +%FT%TZ)] [WARN]  $*"; }
err()  { echo "[$(date -u +%FT%TZ)] [ERROR] $*" >&2; }

mkdir -p docs/evidence/09-teardown

# Phase 0: Confirmation
echo ""
echo "============================================================"
echo "       MAX WEATHER - FORCE TEARDOWN (cloud-nuke)            "
echo "============================================================"
echo ""
echo "This will FORCE-DELETE every AWS resource matching"
echo "'*max-weather*' via cloud-nuke, including:"
echo "  - EKS cluster + Karpenter-provisioned EC2 instances"
echo "  - VPC, subnets, NAT/IGW, NLB/ALB"
echo "  - ECR repositories (emptied first)"
echo "  - Lambda authorizer + Secrets Manager secrets (no recovery)"
echo "  - CloudWatch log groups"
echo "  - tfstate S3 bucket + tflock DynamoDB table"
echo ""
warn "THIS IS IRREVERSIBLE. No ordered drain — cloud-nuke yanks everything."
echo ""
read -rp "Type 'destroy max-weather' to confirm: " CONFIRM
if [[ "$CONFIRM" != "destroy max-weather" ]]; then
  err "Confirmation failed. Aborting teardown."
  exit 1
fi

log "Confirmation received. Starting force teardown..."

# Phase 1: Empty ECR repos (cloud-nuke cannot delete repos containing images)
log "Phase 1: Emptying ECR repositories matching *max-weather*"
ECR_REPOS=$(aws ecr describe-repositories --region "$REGION" \
  --query "repositories[?contains(repositoryName,'max-weather')].repositoryName" \
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

# Phase 2: Force-delete Secrets Manager secrets (skip 7-30d recovery window)
log "Phase 2: Force-deleting Secrets Manager secrets (no recovery)"
for secret_id in "poc-max-weather-authorizer-jwt-secret" "/poc-max-weather/app/config"; do
  aws secretsmanager delete-secret \
    --secret-id "$secret_id" \
    --force-delete-without-recovery \
    --region "$REGION" 2>/dev/null \
    && log "Force-deleted secret: $secret_id" \
    || warn "Secret $secret_id not found or already deleted (continuing)"
done

# Phase 3: cloud-nuke — single sweep of every max-weather resource
log "Phase 3: Running cloud-nuke to wipe ALL max-weather resources (incl. tfstate S3 + tflock DynamoDB)"
if [[ -x "./cloud-nuke_linux_amd64" ]]; then
  ./cloud-nuke_linux_amd64 aws --region "$REGION" --config .cloud-nuke.yaml --force \
    2>&1 | tee docs/evidence/09-teardown/cloud-nuke.log \
    || warn "cloud-nuke had errors - check docs/evidence/09-teardown/cloud-nuke.log"
else
  err "cloud-nuke_linux_amd64 binary not found - cannot proceed with force teardown"
  exit 1
fi

# Phase 4: Final Report
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
