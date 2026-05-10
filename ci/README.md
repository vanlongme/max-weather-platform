# CI/CD Pipeline — max-weather

## Overview

Two Jenkins jobs implement the full CI/CD pipeline:

```
main commit → max-weather-ci → max-weather-deploy (staging) → [input: Approve Prod?] → max-weather-deploy (prod)
```

`max-weather-ci` (upstream) handles lint, test, image build, and push. It passes `IMAGE_TAG`, `ENV`, and
`APP_REPO` to `max-weather-deploy` (downstream), which performs the actual Kubernetes rollout. Both jobs are
created automatically via Job DSL on Jenkins startup — no manual job configuration needed.

## Jobs

### max-weather-ci (Upstream)

Triggered automatically on every push to `main` (via SCM poll every 5 min, or webhook).

1. App lint + test (`cd app && npm ci && npm run lint && npm test`)
2. Lambda authorizer test (`cd lambda-authorizer && npm ci && npm test`)
3. Build and push image to ECR — single env-agnostic tag: `$(APP_REPO):$(GIT_SHA)` (no `staging-` prefix, no `latest`)
4. Trigger `max-weather-deploy` with `ENV=staging` — waits for success
5. Pause at `input` step: **operator must click Approve within 24 hours** to continue to prod
6. Trigger `max-weather-deploy` with `ENV=prod`

### max-weather-deploy (Downstream)

Parameterized job triggered by upstream. Never triggered directly by SCM.

| Parameter | Description |
|-----------|-------------|
| `IMAGE_TAG` | Git short SHA, e.g. `a1b2c3d` — must already exist in ECR |
| `ENV` | Target environment: `staging` or `prod` |
| `APP_REPO` | Full ECR repo URL, e.g. `123456789.dkr.ecr.us-east-1.amazonaws.com/weather-api` |

Pipeline stages:

1. Validate params (`ENV` must be `staging` or `prod`; `IMAGE_TAG` and `APP_REPO` must be non-empty)
2. Verify image exists in ECR via `aws ecr describe-images` (5 retries × 3s sleep for ECR propagation)
3. Apply `kubectl apply -k k8s/overlays/${ENV}` and wait for rollout (`kubectl rollout status --timeout=180s`)
4. Smoke test with `Host: ${ENV}.max-weather.local` header against the NLB
5. On failure (staging only): auto `kubectl rollout undo` then re-fail. Prod failures require manual intervention — no auto-rollback by policy.

## Required Plugins

All plugins managed via `controller.installPlugins` in `k8s/helm/jenkins/values.yaml` — no manual installation needed.

| Plugin | Purpose |
|--------|---------|
| `job-dsl:latest` | Executes `jenkins/jobs.groovy` to create both pipeline jobs on startup |
| `configuration-as-code:latest` | JCasC bootstrap of seed job on Jenkins startup |
| `kubernetes:latest` | Pod-based build agents (no EC2 agent needed) |
| `workflow-aggregator:latest` | Declarative pipeline engine |
| `git:latest` | SCM checkout |
| `pipeline-stage-view:latest` | Pipeline UI visualization |
| `credentials-binding:latest` | Credential injection in `sh` steps |
| `aws-credentials:latest` | AWS IRSA credential handling |
| `docker-workflow:latest` | Docker buildx build steps |

## First-Time Setup

Jenkins is installed via Helm and self-configures on startup:

1. `helm upgrade --install jenkins jenkinsci/jenkins -n jenkins -f k8s/helm/jenkins/values.yaml`
2. Restart controller pod: `kubectl rollout restart statefulset/jenkins -n jenkins`
3. On boot, JCasC reads `controller.JCasC.configScripts.seed-job` and creates a seed freestyle job
4. Seed job auto-runs `jenkins/jobs.groovy` via the Job DSL plugin
5. Job DSL creates `max-weather-ci` and `max-weather-deploy` — both appear in Jenkins UI automatically

For detailed operator workflows (adding jobs, plugins, troubleshooting), see [`jenkins/README.md`](../jenkins/README.md).

## Triggering Deploys

**Staging**: Automatic on every push to `main`. SCM poll (every 5 min) or webhook triggers `max-weather-ci`.

**Production**: Manual gate. After staging deploys successfully, `max-weather-ci` pauses at a Jenkins `input`
step. Open the paused build in the Jenkins UI and click **Promote** within 24 hours.

## Manual Override (Emergency)

```bash
# These targets bypass Jenkins and deploy directly via kubectl
# MANUAL OVERRIDE — use only in emergencies; Jenkins max-weather-deploy is the canonical deploy path
make deploy-staging
make deploy-prod
```

## Environment Variables

| Variable | Source | Description |
|----------|--------|-------------|
| `IMAGE_TAG` | Upstream CI (git SHA) | Immutable image identifier, e.g. `a1b2c3d` |
| `ENV` | Upstream CI | Target environment: `staging` or `prod` |
| `APP_REPO` | Upstream CI (terraform output) | Full ECR URL — passed to avoid terraform init in deploy job |
| `AWS_REGION` | Jenkinsfile env block | AWS region (`us-east-1`) |
| `CLUSTER` | Jenkinsfile env block | EKS cluster name (`max-weather`) |
