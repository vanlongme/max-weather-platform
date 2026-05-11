#!/usr/bin/env bash
# Issue a self-signed HS256 JWT for the max-weather API.
# Usage: TOKEN=$(scripts/issue-token.sh --env staging|prod)
#
# Required args:
#   --env <staging|prod>   — Environment (determines secret name and issuer)
#
# Required env vars (or auto-read from Terraform + Secrets Manager):
#   AUTHORIZER_SECRET_ARN  — ARN of the HS256 signing secret in Secrets Manager
#   AUTHORIZER_JWT_SECRET  — raw secret string (skips Secrets Manager call if set)
#
# Optional env vars:
#   JWT_ISSUER    — iss claim (overrides --env default)
#   JWT_SCOPE     — scope claim (default: weather-api/read)
#   JWT_SUB       — sub claim (default: max-weather-operator)
#   JWT_EXPIRY    — token TTL in seconds (default: 3600)
#   STAGING_DIR   — path to infra/envs/poc (default: infra/envs/poc)
#   AWS_REGION    — AWS region (default: us-east-1)
set -euo pipefail
set +x  # Never trace — would expose secret in CI logs

usage() {
  cat >&2 <<EOF
Usage: $0 --env <staging|prod> [--help]

  --env <staging|prod>   Environment (required). Determines secret name and JWT issuer.
  --help, -h             Show this message.

Examples:
  TOKEN=\$(scripts/issue-token.sh --env staging)
  TOKEN=\$(scripts/issue-token.sh --env prod)
EOF
}

# --- Parse command-line args ---
ENV_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENV_ARG="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo >&2 "ERROR: Unknown argument: $1"
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${ENV_ARG:-}" ]]; then
  echo >&2 "ERROR: --env <staging|prod> is required"
  usage
  exit 2
fi

STAGING_DIR="${STAGING_DIR:-infra/envs/poc}"
AWS_REGION="${AWS_REGION:-us-east-1}"
JWT_SCOPE="${JWT_SCOPE:-weather-api/read}"
JWT_SUB="${JWT_SUB:-max-weather-operator}"
JWT_EXPIRY="${JWT_EXPIRY:-3600}"

# --- Resolve env-specific secret name and issuer ---
case "$ENV_ARG" in
  staging)
    SECRET_NAME="${MASTER_PREFIX:-poc-max-weather}-authorizer-jwt-secret"
    JWT_ISSUER="${JWT_ISSUER:-max-weather-staging}"
    ;;
  prod)
    SECRET_NAME="${MASTER_PREFIX:-poc-max-weather}-authorizer-jwt-secret-prod"
    JWT_ISSUER="${JWT_ISSUER:-max-weather-prod}"
    ;;
  *)
    echo >&2 "ERROR: Invalid --env value: ${ENV_ARG}. Must be 'staging' or 'prod'."
    usage
    exit 2
    ;;
esac

# --- Resolve signing secret ---
if [[ -z "${AUTHORIZER_JWT_SECRET:-}" ]]; then
  # Try to read ARN from env, then fall back to terraform output
  SECRET_ID="${AUTHORIZER_SECRET_ARN:-}"
  if [[ -z "${SECRET_ID:-}" ]]; then
    SECRET_ID=$(cd "$STAGING_DIR" && terraform output -raw authorizer_jwt_secret_arn 2>/dev/null || true)
  fi
  # If no ARN from env or terraform, use secret name (Secrets Manager accepts both ARN and name)
  if [[ -z "${SECRET_ID:-}" ]]; then
    SECRET_ID="${SECRET_NAME}"
  fi
  export AUTHORIZER_JWT_SECRET=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_ID" \
    --region "$AWS_REGION" \
    --query SecretString \
    --output text 2>/dev/null || true)
  if [[ -z "${AUTHORIZER_JWT_SECRET:-}" ]]; then
    echo >&2 "ERROR: Could not fetch secret from Secrets Manager: $SECRET_ID"
    echo >&2 "       Populate with: aws secretsmanager put-secret-value --secret-id \$SECRET_ID --secret-string \"\$(openssl rand -base64 32)\""
    exit 1
  fi
fi

# --- Sign JWT using Node.js (jsonwebtoken is already a lambda-authorizer dep) ---
NODE_BIN="${NODE_BIN:-node}"
TOKEN=$("$NODE_BIN" -e "
const jwt = require('./infra/envs/poc/lambdas/authorizer/node_modules/jsonwebtoken');
const payload = {
  iss: '${JWT_ISSUER}',
  sub: '${JWT_SUB}',
  scope: '${JWT_SCOPE}',
  iat: Math.floor(Date.now() / 1000),
};
const secret = process.env.AUTHORIZER_JWT_SECRET;
const token = jwt.sign(payload, secret, { algorithm: 'HS256', expiresIn: ${JWT_EXPIRY} });
process.stdout.write(token);
") || {
  echo >&2 "ERROR: Failed to sign JWT. Ensure lambda-authorizer/node_modules/ exists."
  echo >&2 "       Run: make lambda-deps"
  exit 1
}

if [[ -z "${TOKEN:-}" ]]; then
  echo >&2 "ERROR: Token signing produced empty output"
  exit 1
fi

printf '%s' "$TOKEN"
