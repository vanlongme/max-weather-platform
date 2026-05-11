#!/usr/bin/env bash
# Set up API Gateway HTTP API, VPC Link, integration, Lambda authorizer, routes, stage.
# Codifies docs/api-gateway-runbook.md.
#
# Required env vars:
#   NLB_DNS              DNS name of the internal NLB (e.g. <id>.elb.us-east-1.amazonaws.com)
#   NLB_LISTENER_ARN     ARN of the NLB TCP listener to integrate with
#
# Optional env vars:
#   CLUSTER_NAME             Prefix for API GW resource names (default: max-weather)
#   AWS_REGION               AWS region (default: us-east-1)
#   LAMBDA_AUTHORIZER_ARN    Lambda function ARN (auto-discovered via aws lambda list-functions if unset)
#   VPC_ID                   VPC ID for the VPC Link SG (auto-discovered if unset)
#   VPC_LINK_SUBNETS         Comma-separated subnet IDs for the VPC Link (auto-discovered if unset)
#
# Flags:
#   --dry-run    Print every AWS mutation as "DRYRUN: <cmd>"; perform no API calls
#   --help       Print this usage and exit 0

set -euo pipefail
IFS=$'\n\t'

usage() {
  sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
}

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo >&2 "ERROR: unknown flag: $arg"; usage >&2; exit 2 ;;
  esac
done

: "${NLB_DNS:?NLB_DNS is required}"
: "${NLB_LISTENER_ARN:?NLB_LISTENER_ARN is required}"
CLUSTER_NAME="${CLUSTER_NAME:-max-weather}"
AWS_REGION="${AWS_REGION:-us-east-1}"
LAMBDA_AUTHORIZER_ARN="${LAMBDA_AUTHORIZER_ARN:-}"
VPC_ID="${VPC_ID:-}"
VPC_LINK_SUBNETS="${VPC_LINK_SUBNETS:-}"

_fmt_cmd() {
  local out=""
  local a
  for a in "$@"; do
    out+=" $a"
  done
  printf '%s' "${out# }"
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRYRUN: %s\n' "$(_fmt_cmd "$@")"
    return 0
  fi
  "$@"
}

capture() {
  local var="$1"; shift
  if [[ "$1" == "--" ]]; then shift; fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRYRUN: %s\n' "$(_fmt_cmd "$@")"
    eval "$var=\"DRYRUN-${var}\""
    return 0
  fi
  local _val
  _val=$("$@")
  eval "$var=\"\$_val\""
}

# --- Auto-discover Lambda authorizer ARN if unset ---
if [[ -z "$LAMBDA_AUTHORIZER_ARN" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRYRUN: aws lambda list-functions --region %s --query "Functions[?contains(FunctionName, \`authorizer\`)].FunctionArn | [0]" --output text\n' "$AWS_REGION"
    LAMBDA_AUTHORIZER_ARN="arn:aws:lambda:${AWS_REGION}:000000000000:function:${CLUSTER_NAME}-authorizer"
  else
    LAMBDA_AUTHORIZER_ARN=$(aws lambda list-functions --region "$AWS_REGION" \
      --query "Functions[?contains(FunctionName, \`authorizer\`)].FunctionArn | [0]" \
      --output text)
    if [[ -z "$LAMBDA_AUTHORIZER_ARN" || "$LAMBDA_AUTHORIZER_ARN" == "None" ]]; then
      echo >&2 "ERROR: could not auto-discover Lambda authorizer ARN; set LAMBDA_AUTHORIZER_ARN"
      exit 1
    fi
  fi
fi

# --- Auto-discover VPC ID if unset (use default VPC) ---
if [[ -z "$VPC_ID" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRYRUN: aws ec2 describe-vpcs --region %s --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text\n' "$AWS_REGION"
    VPC_ID="vpc-dryrun"
  else
    VPC_ID=$(aws ec2 describe-vpcs --region "$AWS_REGION" \
      --filters Name=isDefault,Values=true \
      --query "Vpcs[0].VpcId" --output text)
  fi
fi

# --- Auto-discover subnets if unset ---
if [[ -z "$VPC_LINK_SUBNETS" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRYRUN: aws ec2 describe-subnets --region %s --filters Name=vpc-id,Values=%s --query "Subnets[].SubnetId" --output text\n' "$AWS_REGION" "$VPC_ID"
    VPC_LINK_SUBNETS="subnet-dryrun-a subnet-dryrun-b"
  else
    VPC_LINK_SUBNETS=$(aws ec2 describe-subnets --region "$AWS_REGION" \
      --filters Name=vpc-id,Values="$VPC_ID" \
      --query "Subnets[].SubnetId" --output text)
  fi
fi

# Normalize comma-separated subnets to space-separated for AWS CLI
VPC_LINK_SUBNETS=$(echo "$VPC_LINK_SUBNETS" | tr ',' ' ')

echo "=== Inputs ==="
echo "CLUSTER_NAME=$CLUSTER_NAME"
echo "AWS_REGION=$AWS_REGION"
echo "NLB_DNS=$NLB_DNS"
echo "NLB_LISTENER_ARN=$NLB_LISTENER_ARN"
echo "LAMBDA_AUTHORIZER_ARN=$LAMBDA_AUTHORIZER_ARN"
echo "VPC_ID=$VPC_ID"
echo "VPC_LINK_SUBNETS=$VPC_LINK_SUBNETS"
echo

# === Step 1: Create HTTP API ===
echo "--- Step 1: Create HTTP API ---"
capture API_ID -- aws apigatewayv2 create-api \
  --name "${CLUSTER_NAME}-api" \
  --protocol-type HTTP \
  --region "$AWS_REGION" \
  --query "ApiId" --output text
echo "API_ID=$API_ID"

# === Step 2: Create Security Group for VPC Link ===
echo "--- Step 2: Create VPC Link Security Group ---"
capture VPC_LINK_SG_ID -- aws ec2 create-security-group \
  --group-name "${CLUSTER_NAME}-vpc-link-sg" \
  --description "API Gateway VPC Link SG for ${CLUSTER_NAME}" \
  --vpc-id "$VPC_ID" \
  --region "$AWS_REGION" \
  --query "GroupId" --output text
echo "VPC_LINK_SG_ID=$VPC_LINK_SG_ID"

# === Step 3: Create VPC Link ===
echo "--- Step 3: Create VPC Link ---"
# shellcheck disable=SC2086
capture VPC_LINK_ID -- aws apigatewayv2 create-vpc-link \
  --name "${CLUSTER_NAME}-vpc-link" \
  --subnet-ids $VPC_LINK_SUBNETS \
  --security-group-ids "$VPC_LINK_SG_ID" \
  --region "$AWS_REGION" \
  --query "VpcLinkId" --output text
echo "VPC_LINK_ID=$VPC_LINK_ID"

# === Step 4: Poll VPC Link until AVAILABLE (max 300s) ===
echo "--- Step 4: Wait for VPC Link AVAILABLE ---"
if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'DRYRUN: aws apigatewayv2 get-vpc-link --vpc-link-id %s --region %s --query VpcLinkStatus --output text (poll until AVAILABLE, max 300s, 10s sleep)\n' "$VPC_LINK_ID" "$AWS_REGION"
else
  elapsed=0
  while [[ $elapsed -lt 300 ]]; do
    status=$(aws apigatewayv2 get-vpc-link \
      --vpc-link-id "$VPC_LINK_ID" \
      --region "$AWS_REGION" \
      --query "VpcLinkStatus" --output text)
    echo "  VPC Link status: $status (${elapsed}s)"
    if [[ "$status" == "AVAILABLE" ]]; then break; fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
  if [[ "$status" != "AVAILABLE" ]]; then
    echo >&2 "ERROR: VPC Link not AVAILABLE after 300s (last status: $status)"
    exit 1
  fi
fi

# === Step 5: Create Integration (HTTP_PROXY via VPC Link) ===
echo "--- Step 5: Create Integration ---"
capture INTEGRATION_ID -- aws apigatewayv2 create-integration \
  --api-id "$API_ID" \
  --integration-type HTTP_PROXY \
  --integration-uri "$NLB_LISTENER_ARN" \
  --integration-method ANY \
  --connection-type VPC_LINK \
  --connection-id "$VPC_LINK_ID" \
  --payload-format-version 1.0 \
  --region "$AWS_REGION" \
  --query "IntegrationId" --output text
echo "INTEGRATION_ID=$INTEGRATION_ID"

# === Step 6: Grant API GW permission to invoke Lambda authorizer ===
echo "--- Step 6: Lambda add-permission (idempotent) ---"
if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'DRYRUN: aws lambda add-permission --function-name %s --statement-id apigw-invoke --action lambda:InvokeFunction --principal apigateway.amazonaws.com --region %s\n' "$LAMBDA_AUTHORIZER_ARN" "$AWS_REGION"
else
  if aws lambda add-permission \
      --function-name "$LAMBDA_AUTHORIZER_ARN" \
      --statement-id apigw-invoke \
      --action lambda:InvokeFunction \
      --principal apigateway.amazonaws.com \
      --region "$AWS_REGION" 2>&1 | tee /tmp/api-gw-add-permission.out; then
    echo "  permission added"
  elif grep -q ResourceConflictException /tmp/api-gw-add-permission.out; then
    echo "  permission already present (ResourceConflictException — OK)"
  else
    echo >&2 "ERROR: lambda add-permission failed"
    exit 1
  fi
fi

# === Step 7: Create Authorizer (REQUEST type, payload 2.0, simple responses) ===
echo "--- Step 7: Create Authorizer ---"
AUTHORIZER_URI="arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_AUTHORIZER_ARN}/invocations"
capture AUTHORIZER_ID -- aws apigatewayv2 create-authorizer \
  --api-id "$API_ID" \
  --authorizer-type REQUEST \
  --authorizer-payload-format-version 2.0 \
  --enable-simple-responses \
  --identity-source "\$request.header.Authorization" \
  --name "${CLUSTER_NAME}-authorizer" \
  --authorizer-uri "$AUTHORIZER_URI" \
  --region "$AWS_REGION" \
  --query "AuthorizerId" --output text
echo "AUTHORIZER_ID=$AUTHORIZER_ID"

# === Step 8: Route GET /weather (CUSTOM authorization) ===
echo "--- Step 8: Route GET /weather (CUSTOM) ---"
run aws apigatewayv2 create-route \
  --api-id "$API_ID" \
  --route-key 'GET /weather' \
  --authorization-type CUSTOM \
  --authorizer-id "$AUTHORIZER_ID" \
  --target "integrations/${INTEGRATION_ID}" \
  --region "$AWS_REGION"

# === Step 9: Route GET /healthz (NONE / unauthenticated) ===
echo "--- Step 9: Route GET /healthz (NONE) ---"
run aws apigatewayv2 create-route \
  --api-id "$API_ID" \
  --route-key 'GET /healthz' \
  --authorization-type NONE \
  --target "integrations/${INTEGRATION_ID}" \
  --region "$AWS_REGION"

# === Step 10: Create default stage with auto-deploy ===
echo "--- Step 10: Create \$default stage (auto-deploy) ---"
run aws apigatewayv2 create-stage \
  --api-id "$API_ID" \
  --stage-name "\$default" \
  --auto-deploy \
  --region "$AWS_REGION"

# === Step 11: Print invoke URL and JSON summary ===
echo "--- Step 11: Summary ---"
INVOKE_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com"
echo "Invoke URL: $INVOKE_URL"
cat <<EOF
{
  "api_id": "${API_ID}",
  "vpc_link_id": "${VPC_LINK_ID}",
  "integration_id": "${INTEGRATION_ID}",
  "authorizer_id": "${AUTHORIZER_ID}",
  "invoke_url": "${INVOKE_URL}"
}
EOF
