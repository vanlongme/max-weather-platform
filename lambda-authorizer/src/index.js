'use strict';

const jwt = require('jsonwebtoken');
const jwksRsa = require('jwks-rsa');

let jwksClient;

function getClient() {
  if (!jwksClient) {
    jwksClient = jwksRsa({
      jwksUri: process.env.JWKS_URI,
      cache: true,
      rateLimit: true,
      jwksRequestsPerMinute: 10,
    });
  }
  return jwksClient;
}

function getSigningKey(header) {
  return new Promise((resolve, reject) => {
    getClient().getSigningKey(header.kid, (err, key) => {
      if (err) return reject(err);
      resolve(key.getPublicKey());
    });
  });
}

function buildPolicy(principalId, effect, resource, context) {
  return {
    principalId,
    policyDocument: {
      Version: '2012-10-17',
      Statement: [
        {
          Action: 'execute-api:Invoke',
          Effect: effect,
          Resource: resource,
        },
      ],
    },
    context,
  };
}

async function handler(event) {
  const token = (event.authorizationToken || '').replace(/^Bearer\s+/i, '');

  if (!token) {
    throw new Error('Unauthorized');
  }

  let decoded;
  try {
    decoded = jwt.decode(token, { complete: true });
  } catch (_) {
    throw new Error('Unauthorized');
  }

  if (!decoded || !decoded.header || !decoded.header.kid) {
    throw new Error('Unauthorized');
  }

  const signingKey = await getSigningKey(decoded.header);

  let payload;
  try {
    payload = jwt.verify(token, signingKey, {
      issuer: process.env.ISSUER,
      algorithms: ['RS256'],
    });
  } catch (_) {
    throw new Error('Unauthorized');
  }

  if (payload.token_use !== 'access') {
    throw new Error('Unauthorized');
  }

  const scope = payload.scope || '';
  if (!scope.split(' ').includes('weather-api/read')) {
    throw new Error('Unauthorized');
  }

  return buildPolicy(
    payload.client_id || payload.sub,
    'Allow',
    event.methodArn,
    { client_id: payload.client_id || payload.sub }
  );
}

module.exports = { handler };
