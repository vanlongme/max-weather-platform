# Jenkins E2E Tests

Playwright E2E tests that drive Jenkins through the full CI → staging deploy → approve prod → prod deploy flow.

## Prerequisites

- Node.js 22+
- Running Jenkins instance (deployed via `make deploy-staging` or equivalent)
- kubectl configured for poc-max-weather cluster

## Setup

1. Install dependencies and Playwright browsers:
   ```bash
   cd tests/playwright
   npm ci
   npx playwright install --with-deps chromium
   ```

2. Configure environment:
   ```bash
   cp .env.example .env
   # Edit .env with your Jenkins URL, credentials, and expected stage names
   ```

3. Source environment variables:
   ```bash
   set -a; source .env; set +a
   ```

## Running tests

```bash
cd tests/playwright
npm run test:e2e
```

## Evidence

Evidence is captured to `docs/evidence/jenkins-e2e/`:
- `html-report/` — Playwright HTML report
- `results.json` — JSON test results
- `phase-*.png` — Phase screenshots
- `console-*.log` — Jenkins console logs per job
- `test-results/` — Trace zips on failure (`.zip`)

Open the HTML report:
```bash
npx playwright show-report ../../docs/evidence/jenkins-e2e/html-report
```

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `JENKINS_URL` | Jenkins base URL | `http://jenkins.max-weather.local` |
| `JENKINS_USER` | Jenkins username | `admin` |
| `JENKINS_PASSWORD` | Jenkins admin password | see `secret/jenkins` key `jenkins-admin-password` |
| `APP_REPO` | Git repo URL for app | `https://github.com/org/max-weather` |
| `GIT_SHA` | Git SHA to build | current `git rev-parse HEAD` |
| `EXPECTED_CI_STAGES` | Comma-separated CI stage names | `Checkout,Lint,Test,...` |
| `EXPECTED_DEPLOY_STAGES` | Comma-separated deploy stage names | `Checkout,Deploy Staging,...` |
