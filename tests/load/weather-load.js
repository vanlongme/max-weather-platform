import http from 'k6/http';
import { check, sleep } from 'k6';

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
  const token = __ENV.K6_AUTH_TOKEN || '';
  if (!token) {
    console.warn('K6_AUTH_TOKEN not set — requests will be unauthenticated (expect 401s)');
    console.warn('Run: export K6_AUTH_TOKEN=$(make issue-token) && k6 run tests/load/weather-load.js');
  }
  return { token };
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
      } catch (_) {
        return false;
      }
    },
  });

  sleep(1);
}
