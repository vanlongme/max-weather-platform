// k6 load test for Max Weather API
//
// Stages: ramp 0->10 (30s), sustain 10 (60s), ramp 10->50 (60s),
//         sustain 50 (120s), ramp 50->0 (30s)
//
// Required env: NLB_URL or INVOKE_URL
// Optional: COGNITO_CLIENT_ID, COGNITO_CLIENT_SECRET, COGNITO_TOKEN_ENDPOINT, COGNITO_SCOPE
//
// Run: k6 run tests/load/weather-load.js

import http from 'k6/http';
import { check, sleep } from 'k6';
import encoding from 'k6/encoding';

export const options = {
  stages: [
    { duration: '30s', target: 10 },
    { duration: '60s', target: 10 },
    { duration: '60s', target: 50 },
    { duration: '120s', target: 50 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000'],
    http_req_failed: ['rate<0.05'],
    checks: ['rate>0.95'],
  },
};

export function setup() {
  const clientId = __ENV.COGNITO_CLIENT_ID || '';
  const clientSecret = __ENV.COGNITO_CLIENT_SECRET || '';
  const tokenEndpoint = __ENV.COGNITO_TOKEN_ENDPOINT || '';
  const scope = __ENV.COGNITO_SCOPE || 'weather-api/read';

  if (!tokenEndpoint || !clientId || !clientSecret) {
    console.warn('Cognito env not fully set — requests will be unauthenticated');
    return { token: '' };
  }

  const credentials = `${clientId}:${clientSecret}`;
  const encoded = `Basic ${encoding.b64encode(credentials)}`;

  const res = http.post(
    tokenEndpoint,
    `grant_type=client_credentials&scope=${scope}`,
    {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        Authorization: encoded,
      },
    }
  );

  if (res.status !== 200) {
    console.error(`Token fetch failed: ${res.status} ${res.body}`);
    return { token: '' };
  }

  const body = JSON.parse(res.body);
  return { token: body.access_token || '' };
}

export default function (data) {
  const baseUrl = __ENV.NLB_URL || __ENV.INVOKE_URL || 'http://localhost:8080';
  const token = data.token;
  const headers = token
    ? { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }
    : { 'Content-Type': 'application/json' };

  const cities = [
    { lat: 10.78, lon: 106.70, name: 'HCMC' },
    { lat: 21.03, lon: 105.85, name: 'Hanoi' },
  ];
  const city = cities[__ITER % 2];

  const res = http.get(
    `${baseUrl}/weather?latitude=${city.lat}&longitude=${city.lon}`,
    { headers }
  );

  check(res, {
    [`${city.name} status 200`]: (r) => r.status === 200,
    [`${city.name} has current_weather`]: (r) => {
      try {
        return JSON.parse(r.body).current_weather !== undefined;
      } catch {
        return false;
      }
    },
  });

  sleep(1);
}
