'use strict';

module.exports = {
  port: parseInt(process.env.PORT || '8080', 10),
  logLevel: process.env.LOG_LEVEL || 'info',
  weatherApiBase: process.env.WEATHER_API_BASE || 'https://api.open-meteo.com/v1',
};
