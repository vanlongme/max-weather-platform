const jwt = require('jsonwebtoken');
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');

// Module-level cache for the secret (persist across invocations)
let cachedSecret = null;

const secretsClient = new SecretsManagerClient({
  region: process.env.AWS_REGION || 'us-east-1',
});

/**
 * Fetch the HS256 secret from AWS Secrets Manager
 * Cached at module scope to avoid repeated calls
 */
async function getSecret() {
  if (cachedSecret) {
    return cachedSecret;
  }

  try {
    const secretArn = process.env.AUTHORIZER_SECRET_ARN;
    if (!secretArn) {
      console.error('AUTHORIZER_SECRET_ARN environment variable not set');
      return null;
    }

    const command = new GetSecretValueCommand({ SecretId: secretArn });
    const response = await secretsClient.send(command);
    cachedSecret = response.SecretString || response.SecretBinary;
    return cachedSecret;
  } catch (error) {
    console.error('Failed to retrieve secret:', error.message);
    return null;
  }
}

/**
 * Lambda authorizer handler for HTTP API v2 (SIMPLE format)
 * Returns { isAuthorized: boolean }
 */
async function handler(event) {
  try {
    // Extract Bearer token from headers (case-insensitive)
    const authHeader =
      event.headers?.authorization || event.headers?.Authorization || '';
    const token = authHeader
      .replace(/^Bearer\s+/i, '')
      .trim();

    // No token provided
    if (!token) {
      console.info('Authorization failed: missing token');
      return { isAuthorized: false };
    }

    // Fetch the secret
    const secret = await getSecret();
    if (!secret) {
      console.error('Authorization failed: unable to retrieve secret');
      return { isAuthorized: false };
    }

    // Environment variables with defaults
    const issuer = process.env.ISSUER || 'max-weather-authorizer';
    const requiredScope = process.env.REQUIRED_SCOPE || 'weather-api/read';

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
