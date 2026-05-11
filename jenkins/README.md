# Jenkins Pipelines (Job DSL + JCasC)

Operator guide for the two-job Jenkins CI/CD setup. Pipelines are defined as
code via Job DSL + Configuration as Code (JCasC) — no manual UI configuration
required after the initial `helm upgrade`.

---

## Overview

Two pipeline jobs replace the previous monolithic `Jenkinsfile`:

| Job | Type | Trigger |
|-----|------|---------|
| `max-weather-ci` | Upstream CI | SCM poll (`H/5 * * * *`) or webhook on `main` |
| `max-weather-deploy` | Downstream Deploy | Triggered by `max-weather-ci` via `build job:` step |

The upstream job builds and tests the application, pushes one image tag (`$GIT_SHA`)
to ECR, then automatically deploys to staging. After staging succeeds, an operator
manually approves promotion to production via a Jenkins `input` step (24-hour timeout).

---

## Bootstrap Chain

The following chain runs automatically on every `helm upgrade`:

```
helm upgrade jenkins k8s/helm/jenkins/
  └── JCasC reads controller.JCasC.configScripts.seed-job
        └── Creates Freestyle job: jenkins-job-dsl-seed
              └── Seed job runs jenkins/jobs.groovy (Job DSL)
                    └── Job DSL creates / updates:
                          ├── max-weather-ci  (scriptPath: jenkins/pipelines/ci.Jenkinsfile)
                          └── max-weather-deploy  (scriptPath: jenkins/pipelines/deploy.Jenkinsfile)
```

**Key points**:
- The seed job is entirely defined in `k8s/helm/jenkins/values.yaml` — do not edit it in the Jenkins UI.
- `removedJobAction('DELETE')` in `jobs.groovy` ensures that if a job is removed from the DSL script,
  Jenkins automatically deletes it on the next seed run.
- Changing `jenkins/jobs.groovy` is the canonical way to add, rename, or remove pipeline jobs.
- Changing the Jenkinsfile (`jenkins/pipelines/ci.Jenkinsfile` or `deploy.Jenkinsfile`) does NOT
  require a seed re-run — the pipelines are configured with `branch: main` SCM and pick up
  changes on the next build automatically.

---

## Runtime Flow

```
Developer pushes to main
  └── max-weather-ci triggered (SCM poll or webhook)
        ├── Checkout
        ├── App Lint + Test  (app/junit.xml published)
        ├── Authorizer Test
        ├── Build + Push Image  →  ECR: <repo>:<GIT_SHA>  (single tag, no prefix)
        ├── Deploy to Staging  →  triggers max-weather-deploy (IMAGE_TAG=<sha>, ENV=staging, APP_REPO=<ecr-url>)
        │     └── max-weather-deploy (staging):
        │           ├── Validate Params
        │           ├── Verify ECR Image Exists  (5 retries × 3s)
        │           ├── Update Kustomize Image
        │           ├── Deploy  (kubectl apply -k k8s/overlays/staging)
        │           ├── Smoke Test  (curl -H "Host: staging.max-weather.local" NLB/healthz, 30 retries)
        │           └── On failure: auto-rollback  (kubectl rollout undo, staging only)
        ├── Approve Prod Deploy  ← operator clicks "Promote" in Jenkins UI (24h timeout)
        └── Deploy to Prod  →  triggers max-weather-deploy (IMAGE_TAG=<sha>, ENV=prod, APP_REPO=<ecr-url>)
              └── max-weather-deploy (prod):
                    ├── Same stages as staging
                    └── On failure: NO auto-rollback — fails loudly, manual intervention required
```

---

## Jobs

### `max-weather-ci` (Upstream)

- **File**: `jenkins/pipelines/ci.Jenkinsfile`
- **Trigger**: SCM poll (`H/5 * * * *`) or GitHub webhook on `main`
- **Timeout**: 30 minutes
- **Stages**: Checkout → App Lint+Test → Authorizer Test → Build+Push Image → Deploy to Staging → Approve Prod Deploy → Deploy to Prod
- **Image tag**: Single env-agnostic `$GIT_SHA` (no `staging-` prefix, no `latest`)
- **ECR URL**: Read from `infra/envs/poc` terraform output `weather_api_repository_url`
- **Log retention**: 15 builds

### `max-weather-deploy` (Downstream)

- **File**: `jenkins/pipelines/deploy.Jenkinsfile`
- **Trigger**: Called exclusively by `max-weather-ci` via `build job:` step
- **Timeout**: 20 minutes
- **Concurrency**: `disableConcurrentBuilds(abortPrevious: false)` — queues deploys, never cancels in-flight ones
- **Stages**: Validate Params → Verify ECR Image Exists → Update Kustomize Image → Deploy → Smoke Test
- **Rollback**: Staging only — `kubectl rollout undo deployment/weather-api -n weather-staging` on failure
- **Log retention**: 20 builds

---

## Parameter Contract

The `max-weather-ci` upstream job passes these parameters to `max-weather-deploy`:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `IMAGE_TAG` | string | yes | Git short SHA (e.g. `a1b2c3d`) — must already exist in ECR |
| `ENV` | string | yes | `staging` or `prod` — any other value is rejected with `error()` |
| `APP_REPO` | string | yes | Full ECR repository URL (e.g. `123456789.dkr.ecr.us-east-1.amazonaws.com/weather-api`) — passed from upstream so the deploy job needs no `terraform output` |

---

## Required Plugins

All plugins are bundled via `controller.installPlugins` in `k8s/helm/jenkins/values.yaml`.
No manual plugin installation is needed after `helm upgrade`.

| Plugin | `installPlugins` key | Purpose |
|--------|----------------------|---------|
| Job DSL | `job-dsl:latest` | Executes `jenkins/jobs.groovy` to define pipeline jobs |
| Configuration as Code | `configuration-as-code:latest` | JCasC bootstrap of the seed job on startup |
| Kubernetes | `kubernetes:latest` | Pod templates for ephemeral build agents |
| Git | `git:latest` | SCM checkout in pipelines |
| Pipeline (workflow-aggregator) | `workflow-aggregator:latest` | Declarative pipeline support |
| Pipeline Stage View | `pipeline-stage-view:latest` | Visual stage progress UI |
| AWS Credentials | `aws-credentials:latest` | AWS authentication for ECR and EKS |
| Amazon ECR | `amazon-ecr:latest` | ECR login helper |
| Blue Ocean | `blueocean:latest` | Enhanced pipeline visualization UI |

---

## Operator Workflows

### Add a new pipeline job

1. Open `jenkins/jobs.groovy`.
2. Append a new `pipelineJob('my-job-name') { ... }` block.
3. Commit and push to `main`.
4. Either:
   - **Option A** (recommended): Run `helm upgrade jenkins k8s/helm/jenkins/ -n jenkins` to restart Jenkins — JCasC + seed run automatically.
   - **Option B**: Manually trigger the `jenkins-job-dsl-seed` freestyle job from the Jenkins UI.
5. The new job appears in Jenkins.

### Modify pipeline logic

1. Edit the appropriate Jenkinsfile: `jenkins/pipelines/ci.Jenkinsfile` or `jenkins/pipelines/deploy.Jenkinsfile`.
2. Commit and push to `main`.
3. The next pipeline run picks up the change automatically — no seed re-run needed.

### Delete a job

1. Remove its `pipelineJob('...')` block from `jenkins/jobs.groovy`.
2. Commit, push, and re-run the seed job (Option A or B from _Add a new pipeline job_ above).
3. `removedJobAction('DELETE')` in `jobs.groovy` ensures Jenkins deletes the orphaned job automatically.

### Add a new plugin

1. Append the plugin key to `controller.installPlugins` in `k8s/helm/jenkins/values.yaml`:

   ```yaml
   installPlugins:
     - existing-plugin:latest
     - your-new-plugin:latest   # add here
   ```

2. Apply:

   ```bash
   helm upgrade jenkins k8s/helm/jenkins/ -n jenkins
   kubectl rollout restart statefulset/jenkins -n jenkins
   ```

3. Jenkins restarts, installs the new plugin, and JCasC re-applies on startup.

### Promote a build to production

1. Open the paused `max-weather-ci` build in Jenkins UI (it shows "Paused Input").
2. Click **Promote** on the `Approve Prod Deploy` input step.
3. The prod deploy (`max-weather-deploy` with `ENV=prod`) runs immediately.
4. If the 24-hour timeout elapses without approval, the build is **aborted** (no prod deploy occurs).

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Seed job (`jenkins-job-dsl-seed`) not created after `helm upgrade` | JCasC parse error, or `job-dsl` plugin not installed yet | Check Jenkins startup logs (`kubectl logs -n jenkins statefulset/jenkins -c init`); verify `job-dsl:latest` in `controller.installPlugins`; confirm pod has fully restarted |
| `max-weather-deploy` not triggered after staging succeeds | `build job:` step name mismatch, or downstream job not yet created | Verify the job named `max-weather-deploy` exists in Jenkins UI; check for typos in `ci.Jenkinsfile`; re-run seed if deploy job is missing |
| "Image not found in ECR" error in deploy job | ECR propagation lag after push, or upstream push stage failed | Deploy job retries 5 × 3s before failing; verify `Build + Push Image` stage completed successfully in upstream; check ECR console for the tag |
| Staging deploy auto-rolled back | `kubectl rollout status` timed out or smoke test failed | Check pod logs: `kubectl logs -n weather-staging -l app=weather-api --tail=100`; rollback is intentional staging-only behavior — fix the root cause before re-triggering |
| Prod deploy failed, no rollback triggered | By design — prod fails loudly per policy | Manually re-run `max-weather-deploy` job from Jenkins UI with the previous working `IMAGE_TAG`; or use the Makefile escape hatch: `make deploy-prod` |

---

## Cross-links

- [`ci/README.md`](../ci/README.md) — Developer-facing CI overview: environment variables, first-time setup, triggering deploys
- [`k8s/helm/jenkins/values.yaml`](../k8s/helm/jenkins/values.yaml) — Jenkins Helm config source of truth: plugin list, JCasC seed configScript
- [`k8s/helm/jenkins/README.md`](../k8s/helm/jenkins/README.md) — Helm chart details: access URL, admin password, persistence, POC trade-offs
- [`Makefile`](../Makefile) targets `deploy-staging` / `deploy-prod` — Manual override / escape hatch only (deprecated — prefer the Jenkins job)

---

## POC Note

> **POC only**: `useScriptSecurity: false` is set in `k8s/helm/jenkins/values.yaml` to skip
> the Job DSL script approval prompt. This removes the sandbox approval step for convenience
> in this assessment environment.
>
> **Production**: Enable script security and pre-approve scripts via
> `controller.JCasC.security.globalJobDslSecurityConfiguration.approvedSignatures` before
> disabling `useScriptSecurity`.
