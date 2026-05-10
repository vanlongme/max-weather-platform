#!/usr/bin/env bash
# Runs Postman collection via Newman against staging environment.
# Builds a temp environment file from terraform outputs (never persists secrets).
set -euo pipefail

STAGING_DIR="${STAGING_DIR:-infra/envs/poc}"
REGION="${REGION:-us-east-1}"
TMP_ENV="/tmp/max-weather-env-$$.json"

trap 'rm -f "$TMP_ENV"' EXIT

mkdir -p docs/evidence/05-app

# Pull values from terraform outputs (best-effort; missing values render placeholders)
COGNITO_CLIENT_ID=$(cd "$STAGING_DIR" && terraform output -raw cognito_client_id 2>/dev/null || echo "")
COGNITO_CLIENT_SECRET=$(cd "$STAGING_DIR" && terraform output -raw cognito_client_secret 2>/dev/null || echo "")
COGNITO_TOKEN_ENDPOINT=$(cd "$STAGING_DIR" && terraform output -raw cognito_token_endpoint 2>/dev/null || echo "")
INVOKE_URL="${INVOKE_URL:-$(cd "$STAGING_DIR" && terraform output -raw api_gateway_invoke_url 2>/dev/null || echo "")}"

python3 - "$TMP_ENV" "$COGNITO_CLIENT_ID" "$COGNITO_TOKEN_ENDPOINT" "$COGNITO_CLIENT_SECRET" "$INVOKE_URL" << 'EOF'
import sys, json
out, cid, endpoint, secret, url = sys.argv[1:]
env = {
  "id": "tmp-env",
  "name": "Max Weather — Staging (generated)",
  "values": [
    {"key": "cognito_token_endpoint", "value": endpoint, "type": "default", "enabled": True},
    {"key": "cognito_client_id", "value": cid, "type": "default", "enabled": True},
    {"key": "cognito_client_secret", "value": secret, "type": "secret", "enabled": True},
    {"key": "cognito_scope", "value": "weather-api/read", "type": "default", "enabled": True},
    {"key": "invoke_url", "value": url, "type": "default", "enabled": True},
    {"key": "access_token", "value": "", "type": "secret", "enabled": True},
    {"key": "token_expiry", "value": "0", "type": "default", "enabled": True},
  ],
  "_postman_variable_scope": "environment"
}
with open(out, "w") as f:
  json.dump(env, f, indent=2)
EOF

echo "Running Newman against ${INVOKE_URL:-<unset>}..."
newman run docs/postman/max-weather.postman_collection.json \
  -e "$TMP_ENV" \
  --reporters cli,htmlextra \
  --reporter-htmlextra-export docs/evidence/05-app/postman-report.html \
  2>&1 | tee docs/evidence/05-app/newman-output.txt

echo ""
echo "Report saved to docs/evidence/05-app/postman-report.html"
