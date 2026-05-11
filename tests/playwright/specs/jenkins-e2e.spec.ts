import { test, expect, type APIRequestContext, type Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

const JENKINS_URL = process.env['JENKINS_URL']!;
const JENKINS_USER = process.env['JENKINS_USER']!;
const JENKINS_PASSWORD = process.env['JENKINS_PASSWORD']!;

const DEFAULT_CI_STAGES = [
  'Checkout',
  'App Lint + Test',
  'Authorizer Test',
  'Build + Push Base Image (apko)',
  'Build + Push App Image',
  'Deploy to Staging',
  'Approve Prod Deploy',
  'Deploy to Prod',
].join(',');

const DEFAULT_DEPLOY_STAGES = [
  'Validate Params',
  'Verify ECR Image Exists',
  'Update Kustomize Image',
  'Deploy',
  'Smoke Test',
].join(',');

const EXPECTED_CI_STAGES = (process.env['EXPECTED_CI_STAGES'] || DEFAULT_CI_STAGES)
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

const EXPECTED_DEPLOY_STAGES = (process.env['EXPECTED_DEPLOY_STAGES'] || DEFAULT_DEPLOY_STAGES)
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

const EVIDENCE_DIR = path.resolve(__dirname, '..', '..', '..', 'docs', 'evidence', 'jenkins-e2e');

function authHeader(): string {
  const token = Buffer.from(`${JENKINS_USER}:${JENKINS_PASSWORD}`).toString('base64');
  return `Basic ${token}`;
}

async function waitForQueueItem(
  request: APIRequestContext,
  queueLocation: string,
  timeoutMs: number,
): Promise<number> {
  const deadline = Date.now() + timeoutMs;
  const headers = { Authorization: authHeader() };
  const queueApi = queueLocation.endsWith('/')
    ? `${queueLocation}api/json`
    : `${queueLocation}/api/json`;
  while (Date.now() < deadline) {
    const resp = await request.get(queueApi, { headers });
    if (resp.ok()) {
      const body = await resp.json();
      if (body && body.executable && typeof body.executable.number === 'number') {
        return body.executable.number;
      }
      if (body && body.cancelled === true) {
        throw new Error(`Queue item ${queueLocation} cancelled`);
      }
    }
    await new Promise((r) => setTimeout(r, 5000));
  }
  throw new Error(`Timed out waiting for queue item ${queueLocation}`);
}

async function waitForJenkinsBuild(
  request: APIRequestContext,
  jobName: string,
  buildNum: number,
  predicate: (body: Record<string, unknown>) => boolean,
  timeoutMs: number,
): Promise<Record<string, unknown>> {
  const deadline = Date.now() + timeoutMs;
  const headers = { Authorization: authHeader() };
  let lastBody: Record<string, unknown> | undefined;
  while (Date.now() < deadline) {
    const resp = await request.get(
      `${JENKINS_URL}/job/${jobName}/${buildNum}/api/json`,
      { headers },
    );
    if (resp.ok()) {
      const body = (await resp.json()) as Record<string, unknown>;
      lastBody = body;
      if (predicate(body)) {
        return body;
      }
    }
    await new Promise((r) => setTimeout(r, 15000));
  }
  throw new Error(
    `Build ${jobName}#${buildNum} timed out after ${timeoutMs}ms (last status: ${JSON.stringify(lastBody)})`,
  );
}

async function findDeployBuildForCi(
  request: APIRequestContext,
  ciBuildNumber: number,
  timeoutMs: number,
): Promise<number> {
  const deadline = Date.now() + timeoutMs;
  const headers = { Authorization: authHeader() };
  while (Date.now() < deadline) {
    const resp = await request.get(
      `${JENKINS_URL}/job/max-weather-deploy/api/json?tree=builds[number,actions[causes[shortDescription,upstreamBuild,upstreamProject]]]`,
      { headers },
    );
    if (resp.ok()) {
      const body = (await resp.json()) as {
        builds?: Array<{
          number: number;
          actions?: Array<{ causes?: Array<Record<string, unknown>> }>;
        }>;
      };
      for (const build of body.builds || []) {
        const causes = (build.actions || []).flatMap((a) => a.causes || []);
        const match = causes.some((c) => {
          const desc = String(c['shortDescription'] || '');
          const upstreamBuild = c['upstreamBuild'];
          const upstreamProject = String(c['upstreamProject'] || '');
          if (upstreamProject === 'max-weather-ci' && upstreamBuild === ciBuildNumber) {
            return true;
          }
          return (
            desc.includes(`max-weather-ci`) &&
            desc.includes(String(ciBuildNumber))
          );
        });
        if (match) {
          return build.number;
        }
      }
    }
    await new Promise((r) => setTimeout(r, 10000));
  }
  throw new Error(`No max-weather-deploy build found for ci#${ciBuildNumber}`);
}

async function waitForPendingInput(
  request: APIRequestContext,
  jobName: string,
  buildNum: number,
  timeoutMs: number,
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  const headers = { Authorization: authHeader() };
  while (Date.now() < deadline) {
    const resp = await request.get(
      `${JENKINS_URL}/job/${jobName}/${buildNum}/wfapi/describe`,
      { headers },
    );
    if (resp.ok()) {
      const body = (await resp.json()) as { stages?: Array<{ status?: string }> };
      const paused = (body.stages || []).find(
        (s) => s.status === 'PAUSED_PENDING_INPUT',
      );
      if (paused) {
        return;
      }
    }
    await new Promise((r) => setTimeout(r, 10000));
  }
  throw new Error(`Build ${jobName}#${buildNum} never reached PAUSED_PENDING_INPUT`);
}

async function screenshot(page: Page, name: string): Promise<void> {
  await fs.promises.mkdir(EVIDENCE_DIR, { recursive: true });
  await page.screenshot({
    path: path.join(EVIDENCE_DIR, name),
    fullPage: true,
  });
}

test.describe('Jenkins CI → Staging → Prod promote flow', () => {
  test('full pipeline runs all stages and promote succeeds', async ({ page, request }) => {
    test.setTimeout(2_400_000);

    expect(JENKINS_URL, 'JENKINS_URL must be set').toBeTruthy();
    expect(JENKINS_USER, 'JENKINS_USER must be set').toBeTruthy();
    expect(JENKINS_PASSWORD, 'JENKINS_PASSWORD must be set').toBeTruthy();

    // phase-1: login
    await page.goto('/');
    await page.fill('#j_username', JENKINS_USER);
    await page.fill('input[name="j_password"]', JENKINS_PASSWORD);
    await page.click('button[type="submit"], input[name="Submit"]');
    await expect(page.locator('a[href*="logout"], a[href$="/logout"]').first()).toBeVisible({
      timeout: 15_000,
    });
    await screenshot(page, 'phase-1-login.png');

    // phase-2: verify CI + deploy job stage config
    await page.goto('/job/max-weather-ci/');
    const ciContent = await page.content();
    for (const stage of EXPECTED_CI_STAGES) {
      expect(ciContent, `CI job page must mention stage "${stage}"`).toContain(stage);
    }
    await page.goto('/job/max-weather-deploy/');
    const deployContent = await page.content();
    for (const stage of EXPECTED_DEPLOY_STAGES) {
      expect(deployContent, `Deploy job page must mention stage "${stage}"`).toContain(stage);
    }
    await screenshot(page, 'phase-2-jobs.png');

    // phase-3: trigger CI build
    const buildResp = await request.post(`${JENKINS_URL}/job/max-weather-ci/build`, {
      headers: { Authorization: authHeader() },
    });
    expect([200, 201, 302]).toContain(buildResp.status());
    const locationHeader = buildResp.headers()['location'];
    expect(locationHeader, 'Build trigger must return Location header').toBeTruthy();
    const buildNumber = await waitForQueueItem(request, locationHeader!, 120_000);
    expect(buildNumber).toBeGreaterThan(0);
    await screenshot(page, 'phase-3-triggered.png');

    // phase-4: watch CI build to completion
    const ciBuild = await waitForJenkinsBuild(
      request,
      'max-weather-ci',
      buildNumber,
      (b) => b['building'] === false && b['result'] !== null && b['result'] !== undefined,
      1_200_000,
    );
    expect(ciBuild['result']).toBe('SUCCESS');
    await page.goto(`/job/max-weather-ci/${buildNumber}/`);
    await screenshot(page, 'phase-4-ci-done.png');

    // phase-5: locate deploy build triggered by CI
    const deployBuildNum = await findDeployBuildForCi(request, buildNumber, 300_000);
    expect(deployBuildNum).toBeGreaterThan(0);
    await page.goto(`/job/max-weather-deploy/${deployBuildNum}/`);
    await screenshot(page, 'phase-5-deploy-found.png');

    // phase-6: wait until deploy is paused at input step
    await waitForPendingInput(request, 'max-weather-deploy', deployBuildNum, 900_000);
    await page.goto(`/job/max-weather-deploy/${deployBuildNum}/`);
    await screenshot(page, 'phase-6-paused.png');

    // phase-7: click Approve Prod proceed
    await page.goto(`/job/max-weather-deploy/${deployBuildNum}/input/`);
    const proceedButton = page
      .locator('button:has-text("Proceed"), input[value="Proceed"]')
      .first();
    await proceedButton.waitFor({ state: 'visible', timeout: 30_000 });
    await proceedButton.click();
    await page.waitForLoadState('networkidle', { timeout: 30_000 });
    await screenshot(page, 'phase-7-approved.png');

    // phase-8: wait for prod deploy completion
    const finalBuild = await waitForJenkinsBuild(
      request,
      'max-weather-deploy',
      deployBuildNum,
      (b) => b['building'] === false && b['result'] !== null && b['result'] !== undefined,
      600_000,
    );
    expect(finalBuild['result']).toBe('SUCCESS');
    await page.goto(`/job/max-weather-deploy/${deployBuildNum}/`);
    await screenshot(page, 'phase-8-prod-done.png');

    // phase-9: capture console logs + final screenshot
    await fs.promises.mkdir(EVIDENCE_DIR, { recursive: true });
    const captures: Array<readonly [string, number]> = [
      ['max-weather-ci', buildNumber],
      ['max-weather-deploy', deployBuildNum],
    ];
    for (const [job, num] of captures) {
      const logResp = await request.get(
        `${JENKINS_URL}/job/${job}/${num}/consoleText`,
        { headers: { Authorization: authHeader() } },
      );
      if (logResp.ok()) {
        const logText = await logResp.text();
        await fs.promises.writeFile(
          path.join(EVIDENCE_DIR, `console-${job}-${num}.log`),
          logText,
        );
      }
    }
    await screenshot(page, 'phase-9-final.png');
  });
});
