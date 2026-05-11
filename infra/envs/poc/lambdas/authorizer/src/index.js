const jwt = require('jsonwebtoken');
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');

// Module-level cache keyed by stage name (prevents cross-stage contamination)
const cachedSecrets = {};

const secretsClient = new SecretsManagerClient({
  region: process.env.AWS_REGION || 'us-east-1',
});

/**
 * Resolve stage-specific config from env vars.
 * Stage name is sanitized: "staging" → "STAGING", "$default" → "_DEFAULT"
 * Falls back to legacy single-stage env vars for unknown/default stages.
 */
function resolveStageConfig(stage) {
  const upper = String(stage).toUpperCase().replace(/[^A-Z0-9]/g, '_');
  const secretArn =
    process.env[`${upper}_SECRET_ARN`] || process.env.AUTHORIZER_SECRET_ARN;
  const issuer =
    process.env[`${upper}_ISSUER`] ||
    process.env.JWT_ISSUER ||
    process.env.ISSUER ||
    'max-weather-authorizer';
  const scope =
    process.env[`${upper}_SCOPE`] ||
    process.env.REQUIRED_SCOPE ||
    'weather-api/read';
  return { secretArn, issuer, scope };
}

/**
 * Fetch HS256 secret from Secrets Manager.
 * Cached per stage to avoid repeated SDK calls.
 */
async function getSecret(stage, secretArn) {
  if (cachedSecrets[stage]) {
    return cachedSecrets[stage];
  }

  try {
    if (!secretArn) {
      console.error('No secret ARN resolved for stage:', stage);
      return null;
    }

    const command = new GetSecretValueCommand({ SecretId: secretArn });
    const response = await secretsClient.send(command);
    cachedSecrets[stage] = response.SecretString || response.SecretBinary;
    return cachedSecrets[stage];
  } catch (error) {
    console.error('Failed to retrieve secret for stage', stage, ':', error.message);
    return null;
  }
}

/**
 * Lambda authorizer handler for HTTP API v2 (SIMPLE format)
 * Returns { isAuthorized: boolean }
 */
async function handler(event) {
  try {
    const stage = event.requestContext?.stage || '$default';
    console.info('Stage:', stage);

    // Extract Bearer token from headers (case-insensitive)
    const authHeader =
      event.headers?.authorization || event.headers?.Authorization || '';
    const token = authHeader.replace(/^Bearer\s+/i, '').trim();

    if (!token) {
      console.info('Authorization failed: missing token');
      return { isAuthorized: false };
    }

    const { secretArn, issuer, scope: requiredScope } = resolveStageConfig(stage);

    const secret = await getSecret(stage, secretArn);
    if (!secret) {
      console.error('Authorization failed: unable to retrieve secret for stage:', stage);
      return { isAuthorized: false };
    }

    // Verify JWT
    const payload = jwt.verify(token, secret, {
      algorithms: ['HS256'],
      issuer,
      clockTolerance: 5,
    });

    // Check scope claim
    const scopes = (payload.scope || '')
      .split(' ')
      .map((s) => s.trim())
      .filter((s) => s);

    if (!scopes.includes(requiredScope)) {
      console.info('Authorization failed: insufficient scope');
      return { isAuthorized: false };
    }

    console.info('Authorization successful');
    return { isAuthorized: true };
  } catch (error) {
    console.error('Authorization failed:', error.message);
    return { isAuthorized: false };
  }
}

module.exports = { handler };
