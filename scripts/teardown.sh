#!/usr/bin/env bash
# Full ordered teardown of Max Weather infrastructure.
# 10 phases: confirmation, app, LB wait, karpenter drain, helm, namespaces,
#            manual API GW, terraform destroy, bootstrap (optional),
#            cloud-nuke verify, report.
set -euo pipefail

REGION="${REGION:-us-east-1}"
CLUSTER="${CLUSTER:-max-weather}"
NAMESPACE_STAGING="weather-staging"
NAMESPACE_PROD="weather-prod"
STAGING_DIR="${STAGING_DIR:-infra/envs/poc}"
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
echo "  - EKS cluster and all workloads (incl. Karpenter-provisioned nodes)"
echo "  - VPC, subnets, NAT Gateway, NLB"
echo "  - ECR repositories and images"
echo "  - Lambda authorizer (HS256, Secrets Manager secret)"
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

# Phase 3: Drain Karpenter-provisioned nodes BEFORE uninstalling the controller.
# If we uninstall karpenter first, the in-flight EC2 instances become orphans
# that AWS bills for indefinitely. Deleting NodePools triggers graceful drain.
log "Phase 3: Draining Karpenter-provisioned nodes (delete NodePool/EC2NodeClass)"
if kubectl config current-context &>/dev/null; then
  kubectl delete nodepool --all --ignore-not-found --timeout=180s 2>/dev/null \
    || warn "nodepool delete had issues (CRD may not exist)"
  kubectl delete ec2nodeclass --all --ignore-not-found --timeout=60s 2>/dev/null \
    || warn "ec2nodeclass delete had issues (CRD may not exist)"
  log "Waiting 60s for Karpenter to terminate provisioned EC2 instances..."
  sleep 60
fi

# Phase 3b: Remove CRD-backed kubernetes_manifest resources from tfstate BEFORE
# Phase 4 helm uninstall deletes their CRDs. If left in state, Phase 7
# `terraform destroy` aborts during refresh with:
#   "failed to determine resource GVK: no matches for kind <X>"
# state rm does NOT delete the live K8s objects — helm uninstall + cluster
# destroy will collect them. It only removes them from terraform state so
# the destroy plan/refresh succeeds.
log "Phase 3b: Dropping CRD-backed kubernetes_manifest resources from tfstate"
(cd "$STAGING_DIR" && terraform state rm \
  'module.eks_self_managed_addons.kubernetes_manifest.cluster_secret_store_aws' \
  'module.eks_self_managed_addons.kubernetes_manifest.karpenter_ec2nodeclass_default' \
  'module.eks_self_managed_addons.kubernetes_manifest.karpenter_nodepool_default' \
  2>/dev/null || true)

# Phase 4: Helm Releases (karpenter LAST so it can process node deletions above).
log "Phase 4: Uninstalling Helm releases"
HELM_RELEASES=(
  "jenkins:jenkins"
  "ingress-nginx:ingress-nginx"
  "aws-load-balancer-controller:kube-system"
  "cluster-autoscaler:kube-system"
  "fluent-bit:amazon-cloudwatch"
  "external-secrets:external-secrets"
  "metrics-server:kube-system"
  "karpenter:kube-system"
)
if kubectl config current-context &>/dev/null; then
  for entry in "${HELM_RELEASES[@]}"; do
    release="${entry%%:*}"
    ns="${entry##*:}"
    helm uninstall "$release" -n "$ns" 2>/dev/null || warn "helm uninstall $release skipped (not found)"
  done
fi

# Phase 5: Namespaces
log "Phase 5: Deleting Kubernetes namespaces"
if kubectl config current-context &>/dev/null; then
  kubectl delete ns \
    "$NAMESPACE_STAGING" "$NAMESPACE_PROD" \
    jenkins ingress-nginx amazon-cloudwatch external-secrets \
    --ignore-not-found --timeout=120s 2>/dev/null || warn "Namespace deletion had issues"
fi

# Phase 6: Terraform Destroy (API Gateway now managed by Terraform)
# Targets exclude module.eks_self_managed_addons because its kubernetes_manifest
# resources fail plan-time CRD validation after Phase 4 helm uninstall removed
# the CRDs. Their actual AWS resources (helm releases) live inside the EKS
# cluster and are destroyed when the cluster itself is torn down. Addon state
# was already cleared by Phase 3b state rm.
log "Phase 7: Running terraform destroy for staging environment"
(cd "$STAGING_DIR" && terraform init -reconfigure -input=false) || warn "Terraform init failed"

DESTROY_TARGETS=(
  -target=module.eks
  -target=module.lambda
  -target=module.iam
  -target=module.secrets
  -target=module.ecr
  -target=module.cloudwatch
  -target=module.networking
)

ECR_REPOS=$(aws ecr describe-repositories --region "$REGION" \
  --query "repositories[?contains(repositoryName,'max-weather')].repositoryName" \
  --output text 2>/dev/null || true)
for repo in $ECR_REPOS; do
  IMAGE_IDS=$(aws ecr list-images --repository-name "$repo" --region "$REGION" \
    --query 'imageIds[*]' --output json 2>/dev/null || echo '[]')
  if [[ "$IMAGE_IDS" != "[]" && -n "$IMAGE_IDS" ]]; then
    log "Emptying ECR repository $repo before terraform destroy"
    aws ecr batch-delete-image --repository-name "$repo" --region "$REGION" \
      --image-ids "$IMAGE_IDS" >/dev/null 2>&1 || warn "ECR empty failed for $repo (continuing)"
  fi
done

# Force-delete Secrets Manager secrets immediately so recovery window doesn't block re-apply
log "Phase 6b: Force-deleting Secrets Manager secrets to prevent PendingDeletion collision on re-apply"
for secret_id in "poc-max-weather-authorizer-jwt-secret" "/poc-max-weather/app/config"; do
  aws secretsmanager delete-secret \
    --secret-id "$secret_id" \
    --force-delete-without-recovery \
    --region "$REGION" 2>/dev/null \
    && log "Force-deleted secret: $secret_id" \
    || warn "Secret $secret_id not found or already deleted (continuing)"
done

(cd "$STAGING_DIR" && terraform destroy -auto-approve "${DESTROY_TARGETS[@]}" \
  2>&1 | tee ../../docs/evidence/09-teardown/terraform-destroy.log) \
  || warn "Terraform destroy had errors - check docs/evidence/09-teardown/terraform-destroy.log"

log "Phase 8: Bootstrap teardown (tfstate S3 + DynamoDB)"
(cd infra/bootstrap && terraform destroy -auto-approve \
  2>&1 | tee ../../docs/evidence/09-teardown/bootstrap-destroy.log) \
  || warn "Bootstrap destroy had errors - cloud-nuke phase 9 will mop up"

log "Phase 9: Running cloud-nuke to wipe ALL remaining max-weather resources (incl. tfstate S3 + tflock DynamoDB)"
if [[ -x "./cloud-nuke_linux_amd64" ]]; then
  ./cloud-nuke_linux_amd64 aws --region "$REGION" --config .cloud-nuke.yaml --force \
    2>&1 | tee docs/evidence/09-teardown/cloud-nuke.log \
    || warn "cloud-nuke had errors - check docs/evidence/09-teardown/cloud-nuke.log"
else
  warn "cloud-nuke_linux_amd64 binary not found - account may still contain max-weather resources"
fi

# Phase 10: Final Report
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
