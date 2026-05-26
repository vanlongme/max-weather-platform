# Jenkins Pipelines (Job DSL + JCasC)

Operator guide for the two-job Jenkins CI/CD setup. Pipelines are defined as
code via Job DSL + Configuration as Code (JCasC). The Jenkins controller is
deployed by Terraform as a Helm release inside `infra/envs/poc/eks-self-managed-addons/`
— there is no manual UI configuration after `terraform apply`.

---

## Overview

Two pipeline jobs, no monolithic `Jenkinsfile`:

| Job | Type | Trigger |
|-----|------|---------|
| `max-weather-ci` | Upstream CI | SCM poll (`H/5 * * * *`) or webhook on `main` |
| `max-weather-deploy` | Downstream Deploy | Triggered by `max-weather-ci` via `build job:` step |

Upstream builds + tests the app, pushes a single `$GIT_SHA`-tagged image to ECR,
then auto-deploys to staging. After staging passes, an operator approves the
production promotion via a Jenkins `input` step (24h timeout).

---

## Bootstrap Chain

Runs automatically on every `terraform apply` (or any `helm upgrade` of the
Terraform-managed release):

```
terraform apply  (module.eks_self_managed_addons.helm_release.jenkins)
  └── Helm renders chart with infra/envs/poc/eks-self-managed-addons/values/jenkins.yaml
        └── JCasC reads controller.JCasC.configScripts.seed-job
              └── Creates Freestyle job: jenkins-job-dsl-seed
                    └── Seed job fetches jenkins/jobs.groovy from SCM
                          └── Job DSL creates / updates:
                                ├── max-weather-ci      → jenkins/pipelines/ci.Jenkinsfile
                                └── max-weather-deploy  → jenkins/pipelines/deploy.Jenkinsfile
```

**Key points**:
- The seed job is defined in `infra/envs/poc/eks-self-managed-addons/values/jenkins.yaml` — do NOT edit jobs in the Jenkins UI; the next seed run overwrites them.
- `removedJobAction('DELETE')` in `jobs.groovy` auto-deletes any pipeline whose block is removed from the DSL script.
- Editing `jenkins/jobs.groovy` is the canonical way to add / rename / remove pipeline jobs.
- Editing a Jenkinsfile (`jenkins/pipelines/*.Jenkinsfile`) does NOT require a seed re-run — pipelines are `branch: main` SCM-backed and pick up changes on the next build.

---

## Runtime Flow

```
Developer pushes to main
  └── max-weather-ci triggered (SCM poll or webhook)
        ├── Checkout
        ├── Resolve ECR Repo
        ├── Secret Scan (gitleaks)            — report: gitleaks-report.json
        ├── App Lint + Test                   — app/junit.xml published
        ├── SAST (semgrep)                    — report: semgrep-report.json
        ├── SCA (npm audit)                   — production deps only; report: npm-audit-report.json
        ├── Build Container Image (kaniko)    — builds tarball, NO push yet
        ├── Container Image Scan (trivy)      — scans tarball; report: trivy-image-report.json
        ├── Push Image to ECR                 — kaniko re-runs with cache + --destination
        │                                       (image tag = $GIT_SHA, single tag, no prefix)
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

## Agent Topology

- **Controller-only** Helm release — no static workers.
- **Pod-per-build agents** spawned by the `kubernetes` plugin (templates declared in `values/jenkins.yaml`):
  - `kaniko` — rootless image build + ECR push
  - `kustomize` — `kubectl` / `kustomize edit set image` for deploy job
- **Pod Identity**: `jenkins-agent` ServiceAccount mapped to an IAM role with ECR push + EKS access entry (Edit on `weather-{staging,prod}` namespaces). No static AWS credentials anywhere.
- `node('master')` is forbidden — the controller has no executor.

---

## Jobs

### `max-weather-ci` (Upstream)

- **File**: `jenkins/pipelines/ci.Jenkinsfile`
- **Trigger**: SCM poll (`H/5 * * * *`) or GitHub webhook on `main`
- **Timeout**: 30 minutes
- **Stages**: Checkout → Resolve ECR Repo → Secret Scan (gitleaks) → App Lint+Test → SAST (semgrep) → SCA (npm audit) → Build Container Image (kaniko, no-push tarball) → Container Image Scan (trivy --input tar) → Push Image to ECR (kaniko cache re-run) → Deploy to Staging → Approve Prod Deploy → Deploy to Prod
- **Image tag**: Single env-agnostic `$GIT_SHA` (no `staging-` prefix, no `latest`)
- **ECR URL**: Resolved at runtime from `aws sts get-caller-identity` (no hardcoded account ID)
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
| `APP_REPO` | string | yes | Full ECR repository URL (e.g. `123456789.dkr.ecr.us-east-1.amazonaws.com/poc-max-weather-api-repo`) — passed from upstream so the deploy job needs no `terraform output` |

---

## Plugins & JCasC Source of Truth

Plugins and JCasC config live in **`infra/envs/poc/eks-self-managed-addons/values/jenkins.yaml`**
(`controller.installPlugins`, `controller.JCasC.configScripts`). The Terraform `helm_release.jenkins`
applies them on every `apply`.

| Plugin | Purpose |
|--------|---------|
| `job-dsl` | Executes `jenkins/jobs.groovy` to define pipeline jobs |
| `configuration-as-code` | JCasC bootstrap of the seed job + credentials on startup |
| `kubernetes` | Pod-per-build agent templates (kaniko, kustomize) |
| `git` | SCM checkout in pipelines |
| `workflow-aggregator` | Declarative pipeline support |
| `pipeline-stage-view` | Visual stage progress UI |
| `aws-credentials` | AWS credential binding (paired with Pod Identity for ECR / EKS) |
| `amazon-ecr` | ECR login helper |
| `blueocean` | Enhanced pipeline visualization UI |

Credentials are stored in **AWS Secrets Manager**, synced into Kubernetes by **External Secrets Operator**, and surfaced to Jenkins as credential entries via JCasC — no credential values are ever committed.

---

## Operator Workflows

### Add a new pipeline job

1. Edit `jenkins/jobs.groovy`, append a new `pipelineJob('my-job-name') { ... }` block.
2. Commit and push to `main`.
3. Re-run the seed:
   - **Option A** (recommended): `terraform apply -target=module.eks_self_managed_addons.helm_release.jenkins` — re-applies JCasC + triggers seed on startup.
   - **Option B**: Trigger the `jenkins-job-dsl-seed` freestyle job from the Jenkins UI.
4. New job appears in Jenkins.

### Modify pipeline logic

1. Edit `jenkins/pipelines/ci.Jenkinsfile` or `jenkins/pipelines/deploy.Jenkinsfile`.
2. Commit and push to `main`.
3. The next build picks up the change automatically — no seed re-run needed.

### Delete a job

1. Remove its `pipelineJob('...')` block from `jenkins/jobs.groovy`.
2. Commit, push, re-run the seed (Option A or B above).
3. `removedJobAction('DELETE')` deletes the orphaned job automatically.

### Add a new plugin

1. Append the plugin key to `controller.installPlugins` in
   `infra/envs/poc/eks-self-managed-addons/values/jenkins.yaml`:

   ```yaml
   controller:
     installPlugins:
       - existing-plugin:latest
       - your-new-plugin:latest   # add here
   ```

2. Apply via Terraform:

   ```bash
   cd infra/envs/poc
   terraform apply -target=module.eks_self_managed_addons.helm_release.jenkins
   ```

3. The Jenkins pod restarts, installs the new plugin, and JCasC re-applies.

### Promote a build to production

1. Open the paused `max-weather-ci` build in the Jenkins UI (status: "Paused Input").
2. Click **Promote** on the `Approve Prod Deploy` input step.
3. The prod deploy (`max-weather-deploy` with `ENV=prod`) runs immediately.
4. If the 24-hour timeout elapses without approval, the build is **aborted** (no prod deploy occurs).

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Seed job (`jenkins-job-dsl-seed`) not created after Terraform apply | JCasC parse error, or `job-dsl` plugin not installed yet | `kubectl logs -n jenkins statefulset/jenkins -c init`; verify `job-dsl:latest` in `controller.installPlugins`; confirm pod has fully restarted |
| `max-weather-deploy` not triggered after staging succeeds | `build job:` step name mismatch, or downstream job not yet created | Verify the `max-weather-deploy` job exists in the Jenkins UI; check `ci.Jenkinsfile` for typos; re-run seed if missing |
| "Image not found in ECR" error in deploy job | ECR propagation lag after push, or upstream push stage failed | Deploy job retries 5 × 3s before failing; verify `Build + Push Image` stage completed; check ECR console for the tag |
| Staging deploy auto-rolled back | `kubectl rollout status` timed out or smoke test failed | `kubectl logs -n weather-staging -l app=weather-api --tail=100`; rollback is intentional staging-only behavior — fix the root cause before re-triggering |
| Prod deploy failed, no rollback triggered | By design — prod fails loudly per policy | Re-run `max-weather-deploy` from the Jenkins UI with the previous working `IMAGE_TAG`, or use the Makefile escape hatch `make deploy-prod` |

---

## Security Gates

Four security gate stages run inline in `jenkins/pipelines/ci.Jenkinsfile` between checkout and image push. All scan modes are governed by [`jenkins/security-policy.yaml`](security-policy.yaml) — the single source of truth for thresholds, allowlists, and blocking vs. advisory behaviour. See [`../ARCHITECTURE.md`](../ARCHITECTURE.md) section 5 for the full CI/CD flow with gate positions.

### Gate Layout

```
main push  →  max-weather-ci
  ├── Checkout
  ├── Resolve ECR Repo
  ├── Secret Scan (gitleaks)            — scans tree; report: gitleaks-report.json
  ├── App Lint + Test
  ├── SAST (semgrep)                    — p/nodejs, p/owasp-top-ten, p/javascript; report: semgrep-report.json
  ├── SCA (npm audit)                   — production deps only (--omit=dev); report: npm-audit-report.json
  ├── Build Container Image             — kaniko --no-push --tar-path=image.tar
  ├── Container Image Scan (trivy)      — trivy image --input image.tar; report: trivy-image-report.json
  │                                       Image is NOT pushed unless scan passes (blocking mode)
  ├── Push Image to ECR                 — kaniko cache re-run with --destination
  ├── Deploy to Staging
  ├── Approve Prod Deploy  (24h input)
  └── Deploy to Prod
```

Build–scan–push ordering guarantees a failed `Container Image Scan` blocks ECR push entirely: the previous stage builds the image as a local tarball with `--no-push`, trivy scans the tarball, and only on pass does the subsequent stage re-run kaniko with the registry destination (layer cache hit = effectively push-only).

All scan artifacts are archived to the Jenkins build (`archiveArtifacts`). Each gate reads mode (`advisory`/`blocking`) and thresholds from `security-policy.yaml` via the `securityPolicy` Shared Library var — scanners never hardcode thresholds.

### Policy Flip Procedure

To promote a scan from advisory to blocking:

1. Edit `jenkins/security-policy.yaml`, change the target scan's `mode` field:

   ```yaml
   scans:
     secrets:
       mode: blocking   # was: advisory
   ```

2. Commit and push to `main`.
3. The next CI build picks up the change automatically — no seed re-run, no pod restart.

All four scan keys (`secrets`, `sast`, `sca_npm`, `container`) start as `mode: advisory`. Flip them one at a time; verify build stability before flipping the next.

### Shared Library Usage

The `max-weather-shared` Shared Library (`jenkins/vars/securityPolicy.groovy`) exposes three helpers used inside gate stages:

| Call | Returns | Example |
|------|---------|---------|
| `securityPolicy.blocking('secrets')` | `true` if `mode: blocking`, else `false` | Gate `if (exitCode != 0 && securityPolicy.blocking('secrets'))` |
| `securityPolicy.thresholdFor('sast')` | String severity (e.g. `HIGH`) or `null` | Passed as `--severity ${threshold}` |
| `securityPolicy.allowlistFor('container')` | Path string (e.g. `.trivyignore`) or `null` | Passed as `--ignorefile ${allowlist}` |

The library is loaded via `@Library('max-weather-shared') _` on line 1 of `ci.Jenkinsfile`. `implicit: false` in JCasC means each Jenkinsfile must opt in explicitly.

### Allowlist Table

Suppress a specific scanner finding by adding an entry to the relevant allowlist file and committing it. Suppressions have no TTL — audit them periodically.

| File | Scanner | Purpose | When to add entries |
|------|---------|---------|---------------------|
| `.gitleaks.toml` | gitleaks | Exclude false-positive secret patterns or paths | Test fixtures with dummy credentials, known-safe config values |
| `.semgrepignore` | semgrep | Skip files or directories from SAST scan | Vendored code, generated files, third-party bundles |
| `.trivyignore` | trivy-img | Suppress specific CVE IDs by severity | Unfixed CVEs with confirmed no-impact justification (document the reason in a comment) |

### Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Trivy stage fails with "unable to open DB file" or cache miss every build | `trivy-db-cache` PVC not bound — StorageClass `ebs-csi-default-sc` not available or PVC stuck in `Pending` | `kubectl get pvc trivy-db-cache -n jenkins`; verify EBS CSI driver is running (`kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver`); check `ebs-csi-default-sc` StorageClass exists |
| Container Image Scan fails but image already in ECR | Pipeline ran an older revision that pushed first then scanned, or kaniko cache re-run ran before trivy completed | Verify build order in `ci.Jenkinsfile`: `Build Container Image` → `Container Image Scan` → `Push Image to ECR`. If trivy fails, the `Push Image to ECR` stage must not execute. Check Jenkins stage view for skipped stages |
| Kaniko `--no-push` stage missing `image.tar` for trivy | `WORKSPACE` mismatch between containers, or kaniko OOM-killed mid-build | All containers share `/home/jenkins/agent` workspace via the JNLP pod template — verify `ls -lh ${WORKSPACE}/image.tar` in build logs; bump kaniko memory limit in `ci.Jenkinsfile` pod spec if OOM |

### Follow-ups / Known Gaps

Items deferred from this implementation. None of these are stubs or partial work — they don't exist yet.

| Item | Reason deferred |
|------|----------------|
| Lambda authorizer scan | Authorizer code (`infra/envs/poc/lambdas/authorizer/`) excluded from all scan paths — different deployment lifecycle, no container image |
| SBOM generation (syft) | Removed from POC pipeline — re-introduce when SBOM publication target (e.g. Dependency-Track, GitHub) is selected |
| Image signing (cosign + KMS) | Removed from POC pipeline — re-introduce alongside admission policy that enforces signature verification |
| DAST (ZAP baseline) | Removed from POC pipeline — re-introduce when staging environment has a stable per-build URL and managed test data |
| Kyverno / OPA admission control | Admission webhook infrastructure not provisioned; would require cluster-level policy CRDs outside Jenkins scope |
| IaC scan (checkov / tfsec) | Terraform state contains sensitive outputs; safe scan requires a separate isolated runner with read-only state access, not the current agent pod |
| K8s manifest lint (kube-linter / kubeconform) | Kustomize overlays use dynamic image substitution that breaks static lint without a full `kustomize build` step; deferred until manifest structure stabilises |
| AWS Security Hub integration | Requires Security Hub enabled in the account and an EventBridge rule to route findings — out of scope for POC |
| License compliance (license-checker / FOSSA) | No license policy defined yet; tool selection depends on whether FOSSA SaaS or OSS tooling is approved |

---

## Cross-links

- [`jenkins/jobs.groovy`](jobs.groovy) — Job DSL seed source (canonical job definitions)
- [`jenkins/pipelines/ci.Jenkinsfile`](pipelines/ci.Jenkinsfile) — Upstream CI pipeline
- [`jenkins/pipelines/deploy.Jenkinsfile`](pipelines/deploy.Jenkinsfile) — Downstream deploy pipeline
- [`jenkins/security-policy.yaml`](security-policy.yaml) — Gate modes, thresholds, allowlist paths (single source of truth)
- [`jenkins/vars/securityPolicy.groovy`](vars/securityPolicy.groovy) — Shared Library: `blocking()`, `thresholdFor()`, `allowlistFor()`
- [`infra/envs/poc/eks-self-managed-addons/values/jenkins.yaml`](../infra/envs/poc/eks-self-managed-addons/values/jenkins.yaml) — Helm + JCasC + plugin list (Terraform-managed source of truth)
- [`k8s/README.md`](../k8s/README.md) — Workload manifests deployed by `max-weather-deploy`
- [`Makefile`](../Makefile) `deploy-staging` / `deploy-prod` — manual escape hatch (prefer the Jenkins job)
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — Section 5 CI/CD flow with gate stages; Section 9 Security Posture

---

## POC Note

> **POC only**: `useScriptSecurity: false` is set in `values/jenkins.yaml` to skip the Job DSL script approval prompt. This bypasses the sandbox approval step for assessment convenience.
>
> **Production**: Enable script security and pre-approve scripts via
> `controller.JCasC.security.globalJobDslSecurityConfiguration.approvedSignatures` before
> disabling `useScriptSecurity`.
