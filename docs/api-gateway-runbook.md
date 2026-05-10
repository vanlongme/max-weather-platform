# API Gateway Manual Setup Runbook

This runbook documents how to create and configure an **AWS API Gateway HTTP API** (v2) to front the Max Weather service with Cognito OAuth2 authorization via a Lambda authorizer.

> **Note**: The PDF assessment allows manual API Gateway setup. This runbook provides reproducible step-by-step instructions with all shell commands.

## Prerequisites

```bash
export AWS_REGION=us-east-1

export NLB_DNS=$(kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

export LAMBDA_ARN=$(aws lambda get-function \
  --function-name max-weather-authorizer \
  --query 'Configuration.FunctionArn' \
  --output text --region $AWS_REGION)

export COGNITO_DOMAIN=$(cd infra/envs/poc && terraform output -raw cognito_domain)
export COGNITO_CLIENT_ID=$(cd infra/envs/poc && terraform output -raw cognito_client_id)
export COGNITO_TOKEN_ENDPOINT="https://$COGNITO_DOMAIN/oauth2/token"
```

## Step 1 — Create HTTP API

1. AWS Console → **API Gateway** → **Create API** → **HTTP API** → **Build**
2. **API name**: `max-weather-api`
3. **Description**: Max Weather HTTP API with Lambda authorizer
4. Leave routing empty — configure in Step 3
5. Click **Next** → **Next** → **Create**

## Step 2 — Create HTTP Integration (NLB Proxy)

1. In the API console → **Integrations** → **Manage integrations** → **Create**
2. **Integration type**: HTTP
3. **Method**: `ANY`
4. **URL endpoint**: `http://<NLB_DNS>/{proxy}`
   ```bash
   echo "http://$NLB_DNS/{proxy}"
   ```
5. **Payload format version**: 1.0
6. Click **Create**
7. Note the **Integration ID** (e.g., `abc123`)

## Step 3 — Configure Routes

1. **Routes** → **Create**
2. **Route key**: `ANY /weather/{proxy+}`
3. **Integration target**: Select the HTTP integration created in Step 2
4. Click **Create**

Repeat for health check route:
- **Route key**: `GET /healthz`
- **Integration target**: Same HTTP integration

## Step 4 — Create Lambda Authorizer

1. **Authorization** → **Manage authorizers** → **Create**
2. **Authorizer type**: Lambda
3. **Name**: `cognito-jwt-authorizer`
4. **Lambda function**: `max-weather-authorizer`
   ```bash
   echo "Lambda ARN: $LAMBDA_ARN"
   ```
5. **Response mode**: SIMPLE
6. **Lambda event payload**: v2.0
7. **Identity source**: `$request.header.Authorization`
8. **Authorizer caching**: Enabled, **TTL**: 300 seconds
9. Click **Create**

## Step 5 — Attach Authorizer to Route

1. **Routes** → `ANY /weather/{proxy+}` → **Attach authorization**
2. Select `cognito-jwt-authorizer`
3. Click **Attach authorizer**

> The `/healthz` route intentionally has NO authorizer (liveness check must be unauthenticated).

## Step 6 — Create Deployment Stage

1. **Stages** → **Create**
2. **Stage name**: `prod`
3. **Auto-deploy**: Enabled
4. **Default route throttling**:
   - **Burst limit**: 100
   - **Rate limit**: 50
5. Click **Create**

## Step 7 — Enable Access Logging

1. **Stages** → `prod` → **Logging** → **Edit**
2. **Access logging**: Enabled
3. **Log destination ARN**:
   ```bash
   aws logs describe-log-groups \
     --log-group-name-prefix /aws/apigateway \
     --query 'logGroups[0].arn' \
     --output text --region $AWS_REGION
   ```
4. **Log format** (paste as-is):
   ```json
   {"requestId":"$context.requestId","ip":"$context.identity.sourceIp","requestTime":"$context.requestTime","httpMethod":"$context.httpMethod","routeKey":"$context.routeKey","status":"$context.status","protocol":"$context.protocol","responseLength":"$context.responseLength","integrationStatus":"$context.integration.integrationStatus","authorizer":"$context.authorizer.principalId"}
   ```
5. Click **Save**

## Step 8 — Record Invoke URL

1. **Stages** → `prod` → Copy the **Invoke URL**
2. Format: `https://<api-id>.execute-api.us-east-1.amazonaws.com/prod`
3. Save it:
   ```bash
   INVOKE_URL=https://<api-id>.execute-api.us-east-1.amazonaws.com/prod
   echo "$INVOKE_URL" > docs/evidence/05-api-gateway/api-gateway-invoke-url.txt
   ```

## Step 9 — Fetch Cognito Token and Test (Happy Path)

```bash
TOKEN=$(curl -s -X POST "$COGNITO_TOKEN_ENDPOINT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -u "$COGNITO_CLIENT_ID:$COGNITO_CLIENT_SECRET" \
  -d "grant_type=client_credentials&scope=weather-api/read" \
  | jq -r .access_token)

INVOKE_URL=$(cat docs/evidence/05-api-gateway/api-gateway-invoke-url.txt)

curl -sf -H "Authorization: Bearer $TOKEN" \
  "$INVOKE_URL/weather?latitude=10.78&longitude=106.70" | jq .
```

Expected: HTTP 200, JSON with `current_weather.temperature` field.

## Step 10 — Test Without Token (Negative)

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  "$INVOKE_URL/weather?latitude=10.78&longitude=106.70"
```

Expected: `401` (Unauthorized — authorizer denies).

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| HTTP 502 | NLB unreachable or pod crash | Check `kubectl get pods -n weather-staging`, verify NLB DNS |
| HTTP 401 | Token expired or wrong scope | Re-fetch token; verify scope `weather-api/read` |
| HTTP 403 | Authorizer attached wrong route | Verify route `ANY /weather/{proxy+}` has authorizer |
| HTTP 500 | Lambda authorizer crash | Check CloudWatch `/aws/lambda/max-weather-authorizer` |
| HTTP 404 | Route mismatch | Verify route key is `ANY /weather/{proxy+}` with `+` greedy match |
| Token empty | Wrong client_id/secret or scope | Verify Cognito app client has `weather-api/read` scope allowed |

## Rollback

To remove API Gateway resources:
```bash
API_ID=$(aws apigatewayv2 get-apis \
  --query 'Items[?Name==`max-weather-api`].ApiId' \
  --output text --region $AWS_REGION)

aws apigatewayv2 delete-api --api-id $API_ID --region $AWS_REGION
```

## Future Codification

When time permits, import the API Gateway resource into Terraform:
```bash
terraform import -chdir=infra/envs/poc \
  aws_apigatewayv2_api.max_weather <API_ID>
```

See `infra/envs/poc/` for placeholder `imported.tf` file.
