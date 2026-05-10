'use strict';

const express = require('express');
const pinoHttp = require('pino-http');
const { randomUUID } = require('crypto');
const config = require('./config');
const logger = require('./logger');

const app = express();

app.use(pinoHttp({ logger }));
app.use(express.json());

app.get('/healthz', (_req, res) => {
  res.json({ status: 'ok' });
});

app.get('/version', (_req, res) => {
  res.json({
    version: process.env.APP_VERSION || 'dev',
    commit: process.env.GIT_SHA || 'local',
  });
});

app.get('/weather', async (req, res) => {
  const { latitude, longitude } = req.query;

  if (!latitude || !longitude) {
    return res.status(400).json({ error: 'latitude and longitude query params are required' });
  }

  const url = `${config.weatherApiBase}/forecast?latitude=${encodeURIComponent(latitude)}&longitude=${encodeURIComponent(longitude)}&current_weather=true`;

  const upstream = await globalThis.fetch(url);
  const data = await upstream.json();

  return res.status(upstream.status).json({
    ...data,
    _meta: {
      source: 'open-meteo',
      request_id: randomUUID(),
    },
  });
});

function start() {
  app.listen(config.port, () => {
    logger.info({ port: config.port }, 'weather-api listening');
  });
}

module.exports = { app, start };

if (require.main === module) {
  start();
}
