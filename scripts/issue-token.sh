#!/usr/bin/env bash
# Issue a self-signed HS256 JWT for the max-weather API.
# Usage: TOKEN=$(scripts/issue-token.sh)
#
# Required env vars (or auto-read from Terraform + Secrets Manager):
#   AUTHORIZER_SECRET_ARN  — ARN of the HS256 signing secret in Secrets Manager
#   AUTHORIZER_JWT_SECRET  — raw secret string (skips Secrets Manager call if set)
#
# Optional env vars:
#   JWT_ISSUER    — iss claim (default: max-weather-authorizer)
#   JWT_SCOPE     — scope claim (default: weather-api/read)
#   JWT_SUB       — sub claim (default: max-weather-operator)
#   JWT_EXPIRY    — token TTL in seconds (default: 3600)
#   STAGING_DIR   — path to infra/envs/poc (default: infra/envs/poc)
#   AWS_REGION    — AWS region (default: us-east-1)
set -euo pipefail
set +x  # Never trace — would expose secret in CI logs

STAGING_DIR="${STAGING_DIR:-infra/envs/poc}"
AWS_REGION="${AWS_REGION:-us-east-1}"
JWT_ISSUER="${JWT_ISSUER:-max-weather-authorizer}"
JWT_SCOPE="${JWT_SCOPE:-weather-api/read}"
JWT_SUB="${JWT_SUB:-max-weather-operator}"
JWT_EXPIRY="${JWT_EXPIRY:-3600}"

# --- Resolve signing secret ---
if [[ -z "${AUTHORIZER_JWT_SECRET:-}" ]]; then
  # Try to read ARN from env, then fall back to terraform output
  if [[ -z "${AUTHORIZER_SECRET_ARN:-}" ]]; then
    AUTHORIZER_SECRET_ARN=$(cd "$STAGING_DIR" && terraform output -raw authorizer_jwt_secret_arn 2>/dev/null || true)
  fi
  if [[ -z "${AUTHORIZER_SECRET_ARN:-}" ]]; then
    echo >&2 "ERROR: AUTHORIZER_SECRET_ARN must be set (or resolvable from terraform output)"
    echo >&2 "       Run: make apply  then  make issue-token"
    exit 1
  fi
  AUTHORIZER_JWT_SECRET=$(aws secretsmanager get-secret-value \
    --secret-id "$AUTHORIZER_SECRET_ARN" \
    --region "$AWS_REGION" \
    --query SecretString \
    --output text 2>/dev/null || true)
  if [[ -z "${AUTHORIZER_JWT_SECRET:-}" ]]; then
    echo >&2 "ERROR: Could not fetch secret from Secrets Manager: $AUTHORIZER_SECRET_ARN"
    echo >&2 "       Populate with: aws secretsmanager put-secret-value --secret-id \$AUTHORIZER_SECRET_ARN --secret-string \"\$(openssl rand -base64 32)\""
    exit 1
  fi
fi

# --- Sign JWT using Node.js (jsonwebtoken is already a lambda-authorizer dep) ---
NODE_BIN="${NODE_BIN:-node}"
TOKEN=$("$NODE_BIN" -e "
const jwt = require('./lambda-authorizer/node_modules/jsonwebtoken');
const payload = {
  iss: '${JWT_ISSUER}',
  sub: '${JWT_SUB}',
  scope: '${JWT_SCOPE}',
  iat: Math.floor(Date.now() / 1000),
};
const secret = process.env.AUTHORIZER_JWT_SECRET;
const token = jwt.sign(payload, secret, { algorithm: 'HS256', expiresIn: ${JWT_EXPIRY} });
process.stdout.write(token);
" 2>/dev/null) || {
  echo >&2 "ERROR: Failed to sign JWT. Ensure lambda-authorizer/node_modules/ exists."
  echo >&2 "       Run: make lambda-deps"
  exit 1
}

if [[ -z "${TOKEN:-}" ]]; then
  echo >&2 "ERROR: Token signing produced empty output"
  exit 1
fi

printf '%s' "$TOKEN"
