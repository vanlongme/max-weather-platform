import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './specs',
  testTimeout: 2_400_000,
  expect: {
    timeout: 30_000,
  },
  retries: process.env['CI'] ? 1 : 0,
  workers: 1,
  reporter: [
    ['list'],
    [
      'html',
      {
        outputFolder: '../../docs/evidence/jenkins-e2e/html-report',
        open: 'never',
      },
    ],
    ['json', { outputFile: '../../docs/evidence/jenkins-e2e/results.json' }],
  ],
  use: {
    baseURL: process.env['JENKINS_URL'],
    trace: 'retain-on-failure',
    video: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
});
