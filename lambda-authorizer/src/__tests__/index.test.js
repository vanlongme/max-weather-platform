'use strict';

process.env.JWKS_URI = 'https://cognito-idp.us-east-1.amazonaws.com/us-east-1_test/.well-known/jwks.json';
process.env.ISSUER = 'https://cognito-idp.us-east-1.amazonaws.com/us-east-1_test';

jest.mock('jwks-rsa');
jest.mock('jsonwebtoken');

const jwksRsa = require('jwks-rsa');
const jwt = require('jsonwebtoken');

const VALID_METHOD_ARN = 'arn:aws:execute-api:us-east-1:123:abc/staging/GET/weather';

const VALID_PAYLOAD = {
  sub: 'client123',
  client_id: 'client123',
  token_use: 'access',
  scope: 'weather-api/read',
};

const mockGetPublicKey = jest.fn().mockReturnValue('mock-public-key');
const mockGetSigningKey = jest.fn((_kid, cb) => cb(null, { getPublicKey: mockGetPublicKey }));

beforeEach(() => {
  jest.clearAllMocks();
  jwksRsa.mockReturnValue({ getSigningKey: mockGetSigningKey });
  jwt.decode.mockReturnValue({ header: { kid: 'testkey', alg: 'RS256' } });
  jwt.verify.mockReturnValue(VALID_PAYLOAD);
});

let handler;

beforeAll(() => {
  handler = require('../index').handler;
});

describe('handler — valid token', () => {
  it('returns Allow policy with principalId', async () => {
    const result = await handler({ authorizationToken: 'Bearer validtoken', methodArn: VALID_METHOD_ARN });
    expect(result.policyDocument.Statement[0].Effect).toBe('Allow');
    expect(result.principalId).toBe('client123');
  });
});

describe('handler — missing bearer', () => {
  it('throws Unauthorized when no token', async () => {
    await expect(handler({ authorizationToken: '', methodArn: VALID_METHOD_ARN })).rejects.toThrow('Unauthorized');
  });
});

describe('handler — wrong scope', () => {
  it('throws Unauthorized when scope does not include weather-api/read', async () => {
    jwt.verify.mockReturnValue({ ...VALID_PAYLOAD, scope: 'other/scope' });
    await expect(handler({ authorizationToken: 'Bearer tok', methodArn: VALID_METHOD_ARN })).rejects.toThrow('Unauthorized');
  });
});

describe('handler — wrong token_use', () => {
  it('throws Unauthorized for id token', async () => {
    jwt.verify.mockReturnValue({ ...VALID_PAYLOAD, token_use: 'id' });
    await expect(handler({ authorizationToken: 'Bearer tok', methodArn: VALID_METHOD_ARN })).rejects.toThrow('Unauthorized');
  });
});

describe('handler — expired/invalid token', () => {
  it('throws Unauthorized when jwt.verify throws', async () => {
    jwt.verify.mockImplementation(() => { throw new Error('jwt expired'); });
    await expect(handler({ authorizationToken: 'Bearer tok', methodArn: VALID_METHOD_ARN })).rejects.toThrow('Unauthorized');
  });
});
