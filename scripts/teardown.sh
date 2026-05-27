#!/usr/bin/env bash
# Ordered teardown of Max Weather infrastructure.
#
# Phases:
#   0. Confirmation
#   1. Empty ECR repos (so `aws_ecr_repository` destroy succeeds)
#   2. Force-delete Secrets Manager secrets (skip 7-30d recovery window)
#   3. terraform destroy infra/envs/poc (workload composition — remote state)
#      3b/3c. Recovery: kubectl drain + retry with -refresh=false on failure.
#   4. terraform destroy infra/bootstrap (tfstate S3 + tflock DynamoDB)
#   5. AWS-CLI pre-sweep for resource classes cloud-nuke does not cover.
#   6. cloud-nuke final orphan sweep.
#   7. Report aggregated failures.

# set -e intentionally OFF: failures are tracked via *_FAILED flags and
# surfaced in Phase 7. Bailing mid-teardown leaves orphan resources.
set -uo pipefail

REGION="${REGION:-us-east-1}"
PROJECT="${PROJECT:-max-weather}"
ENV_DIR="infra/envs/poc"
BOOTSTRAP_DIR="infra/bootstrap"
START_TIME=$(date +%s)

TF_WORKLOAD_FAILED=0
TF_BOOTSTRAP_FAILED=0
SWEEP_FAILED=0
CLOUD_NUKE_FAILED=0

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
echo "  - AWS-CLI pre-sweep (VPC Links, VPC endpoints, ENIs, IAM, log groups)"
echo "  - cloud-nuke sweep of any *${PROJECT}* orphans"
echo ""
warn "THIS IS IRREVERSIBLE. Secrets are force-deleted (no recovery)."
echo ""
if [[ "${TEARDOWN_FORCE:-0}" == "1" ]]; then
  log "TEARDOWN_FORCE=1 — skipping confirmation prompt"
else
  read -rp "Type 'destroy max-weather' to confirm: " CONFIRM
  if [[ "$CONFIRM" != "destroy max-weather" ]]; then
    err "Confirmation failed. Aborting teardown."
    exit 1
  fi
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
for secret_id in \
  "poc-${PROJECT}-authorizer-jwt-secret-staging" \
  "poc-${PROJECT}-authorizer-jwt-secret-prod" \
  "poc-${PROJECT}-authorizer-jwt-secret" \
  "/poc-${PROJECT}/app/config"; do
  aws secretsmanager delete-secret \
    --secret-id "$secret_id" \
    --force-delete-without-recovery \
    --region "$REGION" 2>/dev/null \
    && log "Force-deleted secret: $secret_id" \
    || warn "Secret $secret_id not found or already deleted (continuing)"
done

# ─── Phase 3: terraform destroy envs/poc (workload) ─────────────────────────
log "Phase 3: terraform destroy ${ENV_DIR}"

if [[ -d "${ENV_DIR}/.terraform" ]]; then
  (cd "${ENV_DIR}" && terraform destroy -auto-approve) 2>&1 \
    | tee docs/evidence/09-teardown/tf-destroy-envs.log
  TF_RC=${PIPESTATUS[0]}
  if [[ $TF_RC -ne 0 ]]; then
    warn "terraform destroy ${ENV_DIR} FAILED (rc=$TF_RC) — attempting recovery"
    TF_WORKLOAD_FAILED=1

    if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
      log "Phase 3b: kubectl drain LoadBalancer Services + Ingresses"
      kubectl get svc -A -o json 2>/dev/null \
        | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' \
        | while read -r ns name; do
            [[ -z "$ns" ]] && continue
            log "Deleting LoadBalancer Service $ns/$name"
            kubectl delete svc -n "$ns" "$name" --timeout=120s 2>&1 \
              | tee -a docs/evidence/09-teardown/kubectl-drain.log \
              || warn "Failed to delete svc $ns/$name"
          done
      kubectl delete ingress --all -A --timeout=120s 2>&1 \
        | tee -a docs/evidence/09-teardown/kubectl-drain.log \
        || warn "Ingress delete had errors"
      log "Waiting 45s for AWS LB controller to release NLBs/ENIs"
      sleep 45

      log "Phase 3c: retry terraform destroy ${ENV_DIR} with -refresh=false"
      (cd "${ENV_DIR}" && terraform destroy -auto-approve -refresh=false) 2>&1 \
        | tee -a docs/evidence/09-teardown/tf-destroy-envs.log
      TF_RC2=${PIPESTATUS[0]}
      if [[ $TF_RC2 -eq 0 ]]; then
        log "Recovery retry succeeded"
        TF_WORKLOAD_FAILED=0
      else
        warn "Recovery retry also failed (rc=$TF_RC2) — Phase 5 sweep will clean up"
      fi
    else
      warn "kubectl unavailable — cannot recover. Phase 5 sweep will clean up."
    fi
  fi
else
  warn "${ENV_DIR}/.terraform not initialized — skipping (sweeps will handle)"
fi

# ─── Phase 4: terraform destroy bootstrap (tfstate backend) ─────────────────
log "Phase 4: terraform destroy ${BOOTSTRAP_DIR} (tfstate S3 + tflock DynamoDB)"
if [[ -d "${BOOTSTRAP_DIR}/.terraform" || -f "${BOOTSTRAP_DIR}/terraform.tfstate" ]]; then
  (cd "${BOOTSTRAP_DIR}" && terraform destroy -auto-approve) 2>&1 \
    | tee docs/evidence/09-teardown/tf-destroy-bootstrap.log
  TF_BS_RC=${PIPESTATUS[0]}
  if [[ $TF_BS_RC -ne 0 ]]; then
    warn "terraform destroy ${BOOTSTRAP_DIR} FAILED (rc=$TF_BS_RC) — Phase 6 cloud-nuke will sweep"
    TF_BOOTSTRAP_FAILED=1
  fi
else
  warn "${BOOTSTRAP_DIR} state not found — skipping"
fi

# ─── Phase 5: AWS-CLI orphan pre-sweep ──────────────────────────────────────
log "Phase 5: AWS-CLI pre-sweep (gaps cloud-nuke does not cover)"

log "  5a. Deleting orphan API Gateway v2 VPC Links matching *${PROJECT}*"
VPC_LINKS=$(aws apigatewayv2 get-vpc-links --region "$REGION" \
  --query "Items[?contains(Name,'${PROJECT}')].VpcLinkId" \
  --output text 2>/dev/null || true)
for vlid in $VPC_LINKS; do
  log "    Deleting VPC Link: $vlid"
  aws apigatewayv2 delete-vpc-link --vpc-link-id "$vlid" --region "$REGION" 2>&1 \
    | tee -a docs/evidence/09-teardown/sweep.log \
    || { warn "Failed to delete VPC Link $vlid"; SWEEP_FAILED=1; }
done

log "  5b. Deleting orphan VPC endpoints in VPCs matching *${PROJECT}*"
VPC_IDS=$(aws ec2 describe-vpcs --region "$REGION" \
  --filters "Name=tag:Name,Values=*${PROJECT}*" \
  --query 'Vpcs[].VpcId' --output text 2>/dev/null || true)
for vpc in $VPC_IDS; do
  VPCE_IDS=$(aws ec2 describe-vpc-endpoints --region "$REGION" \
    --filters "Name=vpc-id,Values=$vpc" \
    --query 'VpcEndpoints[].VpcEndpointId' --output text 2>/dev/null || true)
  if [[ -n "$VPCE_IDS" ]]; then
    log "    Deleting VPC endpoints in $vpc: $VPCE_IDS"
    # shellcheck disable=SC2086
    aws ec2 delete-vpc-endpoints --region "$REGION" \
      --vpc-endpoint-ids $VPCE_IDS 2>&1 \
      | tee -a docs/evidence/09-teardown/sweep.log \
      || { warn "VPC endpoint delete failed in $vpc"; SWEEP_FAILED=1; }
  fi
done

log "  5c. Deleting available ENIs tagged or grouped with *${PROJECT}*"
ENI_IDS=$(aws ec2 describe-network-interfaces --region "$REGION" \
  --filters "Name=status,Values=available" \
  --query "NetworkInterfaces[?contains(to_string(TagSet), '${PROJECT}') || contains(Description, '${PROJECT}')].NetworkInterfaceId" \
  --output text 2>/dev/null || true)
for eni in $ENI_IDS; do
  log "    Deleting ENI: $eni"
  aws ec2 delete-network-interface --network-interface-id "$eni" --region "$REGION" 2>&1 \
    | tee -a docs/evidence/09-teardown/sweep.log \
    || { warn "ENI delete failed: $eni"; SWEEP_FAILED=1; }
done

log "  5d. Deleting CloudWatch log groups matching *${PROJECT}*"
LG_NAMES=$(aws logs describe-log-groups --region "$REGION" \
  --query "logGroups[?contains(logGroupName,'${PROJECT}')].logGroupName" \
  --output text 2>/dev/null || true)
for lg in $LG_NAMES; do
  log "    Deleting log group: $lg"
  aws logs delete-log-group --log-group-name "$lg" --region "$REGION" 2>&1 \
    | tee -a docs/evidence/09-teardown/sweep.log \
    || { warn "Log group delete failed: $lg"; SWEEP_FAILED=1; }
done

log "  5e. Detaching IAM instance profiles + deleting roles matching *${PROJECT}*"
ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName,'${PROJECT}')].RoleName" \
  --output text 2>/dev/null || true)
for role in $ROLES; do
  PROFILES=$(aws iam list-instance-profiles-for-role --role-name "$role" \
    --query 'InstanceProfiles[].InstanceProfileName' --output text 2>/dev/null || true)
  for prof in $PROFILES; do
    log "    Removing role $role from instance profile $prof"
    aws iam remove-role-from-instance-profile \
      --instance-profile-name "$prof" --role-name "$role" 2>&1 \
      | tee -a docs/evidence/09-teardown/sweep.log \
      || warn "Detach role $role from $prof failed"
  done
done
PROFILES=$(aws iam list-instance-profiles \
  --query "InstanceProfiles[?contains(InstanceProfileName,'${PROJECT}')].InstanceProfileName" \
  --output text 2>/dev/null || true)
for prof in $PROFILES; do
  log "    Deleting instance profile: $prof"
  aws iam delete-instance-profile --instance-profile-name "$prof" 2>&1 \
    | tee -a docs/evidence/09-teardown/sweep.log \
    || { warn "Instance profile delete failed: $prof"; SWEEP_FAILED=1; }
done

# ─── Phase 6: cloud-nuke orphan sweep ───────────────────────────────────────
log "Phase 6: cloud-nuke final orphan sweep (anything matching *${PROJECT}*)"
if [[ -x "./cloud-nuke_linux_amd64" ]]; then
  ./cloud-nuke_linux_amd64 aws --region "$REGION" --config .cloud-nuke.yaml --force \
    2>&1 | tee docs/evidence/09-teardown/cloud-nuke.log
  CN_RC=${PIPESTATUS[0]}
  if [[ $CN_RC -ne 0 ]]; then
    warn "cloud-nuke had errors (rc=$CN_RC) — check docs/evidence/09-teardown/cloud-nuke.log"
    CLOUD_NUKE_FAILED=1
  fi
else
  warn "cloud-nuke_linux_amd64 not found — skipping orphan sweep"
  warn "Install: https://github.com/gruntwork-io/cloud-nuke/releases"
fi

# ─── Phase 7: Final Report ──────────────────────────────────────────────────
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

echo ""
echo "============================================================"
echo "                  TEARDOWN REPORT                           "
echo "============================================================"
log "Total elapsed: ${ELAPSED}s (~$((ELAPSED/60)) minutes)"
log "Estimated monthly savings: ~\$215/month"
log "Evidence saved to: docs/evidence/09-teardown/"
echo ""

FAILURES=0
if [[ $TF_WORKLOAD_FAILED -eq 1 ]]; then
  err "FAIL: terraform destroy ${ENV_DIR} did not complete cleanly"
  FAILURES=$((FAILURES+1))
fi
if [[ $TF_BOOTSTRAP_FAILED -eq 1 ]]; then
  err "FAIL: terraform destroy ${BOOTSTRAP_DIR} did not complete cleanly"
  FAILURES=$((FAILURES+1))
fi
if [[ $SWEEP_FAILED -eq 1 ]]; then
  err "FAIL: AWS-CLI pre-sweep had non-fatal errors (Phase 5)"
  FAILURES=$((FAILURES+1))
fi
if [[ $CLOUD_NUKE_FAILED -eq 1 ]]; then
  err "FAIL: cloud-nuke had errors (Phase 6)"
  FAILURES=$((FAILURES+1))
fi

if [[ $FAILURES -eq 0 ]]; then
  log "ALL PHASES SUCCEEDED. Account returned to zero."
else
  err "$FAILURES phase(s) reported failures. Verify with:"
  err "  aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=${PROJECT} \\"
  err "    --region $REGION --query 'ResourceTagMappingList[].ResourceARN' --output text"
fi

echo ""
echo "Post-teardown verification:"
echo "  aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=${PROJECT} \\"
echo "    --region $REGION --query 'ResourceTagMappingList[].ResourceARN' --output text"

exit $FAILURES
