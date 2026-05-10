#!/usr/bin/env bash
# Fetches Cognito OAuth2 token using client_credentials grant.
# Usage: TOKEN=$(scripts/get-token.sh)
#
# Reads COGNITO_TOKEN_ENDPOINT, COGNITO_CLIENT_ID, COGNITO_CLIENT_SECRET from env
# OR falls back to terraform output from infra/envs/staging.
set -euo pipefail

# Never trace - would expose secret in CI logs
set +x

STAGING_DIR="${STAGING_DIR:-infra/envs/staging}"
REGION="${REGION:-us-east-1}"

# If env vars not set, pull from terraform output
if [[ -z "${COGNITO_CLIENT_ID:-}" ]]; then
  COGNITO_CLIENT_ID=$(cd "$STAGING_DIR" && terraform output -raw cognito_client_id 2>/dev/null)
fi
if [[ -z "${COGNITO_TOKEN_ENDPOINT:-}" ]]; then
  COGNITO_TOKEN_ENDPOINT=$(cd "$STAGING_DIR" && terraform output -raw cognito_token_endpoint 2>/dev/null)
fi
if [[ -z "${COGNITO_CLIENT_SECRET:-}" ]]; then
  COGNITO_CLIENT_SECRET=$(cd "$STAGING_DIR" && terraform output -raw cognito_client_secret 2>/dev/null)
fi
COGNITO_SCOPE="${COGNITO_SCOPE:-weather-api/read}"

if [[ -z "${COGNITO_CLIENT_ID:-}" || -z "${COGNITO_CLIENT_SECRET:-}" || -z "${COGNITO_TOKEN_ENDPOINT:-}" ]]; then
  echo >&2 "ERROR: COGNITO_CLIENT_ID, COGNITO_CLIENT_SECRET, COGNITO_TOKEN_ENDPOINT must be set"
  echo >&2 "       (either via env or terraform output in $STAGING_DIR)"
  exit 1
fi

# Build Basic auth header
CREDENTIALS=$(printf '%s:%s' "$COGNITO_CLIENT_ID" "$COGNITO_CLIENT_SECRET" | base64 | tr -d '\n')

RESPONSE=$(curl -sf \
  -X POST "$COGNITO_TOKEN_ENDPOINT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Authorization: Basic $CREDENTIALS" \
  -d "grant_type=client_credentials&scope=$COGNITO_SCOPE" \
  || { echo >&2 "ERROR: curl to Cognito token endpoint failed"; exit 1; })

TOKEN=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null)
if [[ -z "$TOKEN" ]]; then
  echo >&2 "ERROR: No access_token in response"
  echo >&2 "Response: $(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); d.pop('access_token',None); print(d)" 2>/dev/null || echo "$RESPONSE")"
  exit 2
fi

printf '%s' "$TOKEN"
