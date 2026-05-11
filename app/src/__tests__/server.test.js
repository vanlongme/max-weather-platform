'use strict';

const request = require('supertest');
const { app } = require('../server');

describe('GET /healthz', () => {
  it('returns 200 with status ok', async () => {
    const res = await request(app).get('/healthz');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: 'ok' });
  });
});

describe('GET /version', () => {
  it('returns 200 with version field', async () => {
    const res = await request(app).get('/version');
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('version');
    expect(res.body).toHaveProperty('commit');
  });
});

describe('GET /weather', () => {
  beforeEach(() => {
    globalThis.fetch = jest.fn();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('returns 200 with current_weather and _meta', async () => {
    globalThis.fetch.mockResolvedValueOnce({
      status: 200,
      json: async () => ({ current_weather: { temperature: 25 } }),
    });

    const res = await request(app).get('/weather?latitude=21.03&longitude=105.85');
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('current_weather');
    expect(res.body).toHaveProperty('_meta');
    expect(res.body._meta.source).toBe('open-meteo');
  });

  it('returns 400 when latitude is missing', async () => {
    const res = await request(app).get('/weather?longitude=105.85');
    expect(res.status).toBe(400);
    expect(res.body).toHaveProperty('error');
  });

  it('returns 400 when longitude is missing', async () => {
    const res = await request(app).get('/weather?latitude=21.03');
    expect(res.status).toBe(400);
    expect(res.body).toHaveProperty('error');
  });

  it('returns 400 when both params missing', async () => {
    const res = await request(app).get('/weather');
    expect(res.status).toBe(400);
  });
});
