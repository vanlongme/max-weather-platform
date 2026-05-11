#!/usr/bin/env bash
set -euo pipefail

STAGING_DIR="${STAGING_DIR:-infra/envs/poc}"
REGION="${REGION:-us-east-1}"
TMP_ENV="/tmp/max-weather-env-$$.json"

trap 'rm -f "$TMP_ENV"' EXIT

mkdir -p docs/evidence/05-app

INVOKE_URL="${INVOKE_URL:-$(cd "$STAGING_DIR" && terraform output -raw api_gateway_invoke_url 2>/dev/null || echo "")}"
JWT_SECRET_ARN="${JWT_SECRET_ARN:-$(cd "$STAGING_DIR" && terraform output -raw authorizer_jwt_secret_arn 2>/dev/null || echo "")}"
JWT_SECRET="${JWT_SECRET:-}"
if [[ -z "$JWT_SECRET" && -n "$JWT_SECRET_ARN" ]]; then
  JWT_SECRET=$(aws secretsmanager get-secret-value \
    --secret-id "$JWT_SECRET_ARN" \
    --region "$REGION" \
    --query SecretString \
    --output text 2>/dev/null || echo "")
fi

python3 - "$TMP_ENV" "$JWT_SECRET" "$INVOKE_URL" << 'EOF'
import sys, json
out, secret, url = sys.argv[1:]
env = {
  "id": "tmp-env",
  "name": "Max Weather — Staging (generated)",
  "values": [
    {"key": "jwt_secret", "value": secret, "type": "secret", "enabled": True},
    {"key": "invoke_url", "value": url, "type": "default", "enabled": True},
    {"key": "access_token", "value": "", "type": "secret", "enabled": True},
  ],
  "_postman_variable_scope": "environment"
}
with open(out, "w") as f:
  json.dump(env, f, indent=2)
EOF

echo "Running Newman against ${INVOKE_URL:-<unset>}..."
npx --yes newman run docs/postman/max-weather.postman_collection.json \
  -e "$TMP_ENV" \
  --reporters cli,htmlextra \
  --reporter-htmlextra-export docs/evidence/05-app/postman-report.html \
  2>&1 | tee docs/evidence/05-app/newman-output.txt

echo ""
echo "Report saved to docs/evidence/05-app/postman-report.html"
