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
        ├── App Lint + Test  (app/junit.xml published)
        ├── Trivy Container Image Scan  (fails on HIGH/CRITICAL)
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
- **Stages**: Checkout → App Lint+Test → Trivy Container Image Scan → Build+Push Image → Deploy to Staging → Approve Prod Deploy → Deploy to Prod
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

Four security gate stages run in `jenkins/pipelines/ci.Jenkinsfile`. All scan modes are governed by [`jenkins/security-policy.yaml`](security-policy.yaml) — the single source of truth for thresholds, allowlists, and blocking vs. advisory behaviour. See [`../ARCHITECTURE.md`](../ARCHITECTURE.md) section 5 for the full CI/CD flow with gate positions.

### Gate Layout

```
main push  →  max-weather-ci
  ├── Checkout
  ├── Resolve ECR Repo
  ├── Pre-Source Gates  (parallel)
  │     ├── Secret Scan (gitleaks)     — scans git history; report: gitleaks-report.json
  │     ├── SAST (semgrep)             — p/nodejs, p/owasp-top-ten, p/javascript; report: semgrep-report.json
  │     ├── SCA FS (trivy-fs)          — vuln+secret scan of app/; report: trivy-fs-report.json
  │     └── SCA NPM (npm audit)        — production deps only (--omit=dev); report: npm-audit-report.json
  ├── App Lint + Test
  ├── Build + Push App Image (kaniko)
  ├── Image Gates  (parallel)
  │     ├── Trivy Image                — container CVE scan; report: trivy-image-report.json
  │     ├── SBOM (syft)                — SPDX-JSON artifact: sbom.spdx.json
  │     └── Cosign Sign                — KMS sign by digest (alias/max-weather-cosign-signer)
  ├── Deploy to Staging
  ├── Runtime Gates
  │     └── ZAP Baseline               — DAST against staging API GW + minted JWT; report: zap-report.json
  ├── Approve Prod Deploy  (24h input)
  ├── Pre-Prod Gates  (parallel)
  │     ├── Cosign Verify              — ALWAYS blocking; re-verifies digest before prod deploy
  │     └── Drift Re-scan              — trivy image re-scan to catch CVEs published since Image Gates
  └── Deploy to Prod
```

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

All 9 scan keys start as `mode: advisory`. Flip them one at a time; verify build stability before flipping the next.

### Shared Library Usage

The `max-weather-shared` Shared Library (`jenkins/vars/securityPolicy.groovy`) exposes three helpers used inside gate stages:

| Call | Returns | Example |
|------|---------|---------|
| `securityPolicy.blocking('secrets')` | `true` if `mode: blocking`, else `false` | Gate `if (exitCode != 0 && securityPolicy.blocking('secrets'))` |
| `securityPolicy.thresholdFor('sast')` | String severity (e.g. `HIGH`) or `null` | Passed as `--severity ${threshold}` |
| `securityPolicy.allowlistFor('sca_fs')` | Path string (e.g. `.trivyignore`) or `null` | Passed as `--ignorefile ${allowlist}` |

The library is loaded via `@Library('max-weather-shared') _` on line 1 of `ci.Jenkinsfile`. `implicit: false` in JCasC means each Jenkinsfile must opt in explicitly.

### Allowlist Table

Suppress a specific scanner finding by adding an entry to the relevant allowlist file and committing it. Suppressions have no TTL — audit them periodically.

| File | Scanner | Purpose | When to add entries |
|------|---------|---------|---------------------|
| `.gitleaks.toml` | gitleaks | Exclude false-positive secret patterns or paths | Test fixtures with dummy credentials, known-safe config values |
| `.semgrepignore` | semgrep | Skip files or directories from SAST scan | Vendored code, generated files, third-party bundles |
| `.trivyignore` | trivy-fs, trivy-img, drift re-scan | Suppress specific CVE IDs by severity | Unfixed CVEs with confirmed no-impact justification (document the reason in a comment) |
| `.zap/baseline.conf` | ZAP baseline | Ignore specific ZAP rule IDs or alert types | False positives confirmed safe for the API's threat model |

### Cosign Verify Procedure

To verify a signed image outside CI (e.g. post-incident audit):

```bash
cosign verify \
  --key awskms:///alias/max-weather-cosign-signer \
  <ECR_REPO>@<DIGEST>
```

Where `<ECR_REPO>` is the full ECR URI (e.g. `123456789.dkr.ecr.us-east-1.amazonaws.com/poc-max-weather-api-repo`) and `<DIGEST>` is the `sha256:...` digest from ECR. The `jenkins-agent` IAM role has KMS Verify permission. Any IAM principal with `kms:Verify` on `alias/max-weather-cosign-signer` can run this.

The `Pre-Prod Gates / Cosign Verify` stage runs this check automatically before every prod deploy and always runs in blocking mode regardless of the `verify` key's `mode` value in `security-policy.yaml` (`set -eu` makes any non-zero exit fatal).

### Fixture Test Harness

`jenkins/tests/security-policy-fixtures/` contains minimal YAML fixtures and a Groovy unit test for `securityPolicy.groovy`. Run locally (requires Groovy 3+):

```bash
cd jenkins
groovy tests/security-policy-fixtures/securityPolicySpec.groovy
```

Tests cover: `blocking()` returns `false` for advisory keys, `true` for blocking keys; `thresholdFor()` returns correct severity; `allowlistFor()` returns correct path.

### Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Trivy stages fail with "unable to open DB file" or cache miss every build | `trivy-db-cache` PVC not bound — StorageClass `ebs-csi-default-sc` not available or PVC stuck in `Pending` | `kubectl get pvc trivy-db-cache -n jenkins`; verify EBS CSI driver is running (`kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver`); check `ebs-csi-default-sc` StorageClass exists |
| ZAP stage skipped or exits with "STAGING_URL not set" | `STAGING_URL` Jenkins env var not configured, and `terraform output` call failed (Terraform state not accessible from agent pod) | Set `STAGING_URL` as a Jenkins global environment variable in JCasC (`jenkins.globalNodeProperties`) or as a pipeline credential; value: `$(cd infra/envs/poc && terraform output -raw api_gateway_invoke_url_staging)` |
| Cosign sign/verify fails with "AccessDenied" or KMS permission error | `jenkins-agent` IAM role missing `kms:Sign` or `kms:Verify` on `alias/max-weather-cosign-signer` — Pod Identity binding may have drifted | Check Pod Identity association: `aws eks list-pod-identity-associations --cluster-name poc-max-weather-cluster`; verify IAM policy attached to the agent role includes `kms:Sign`, `kms:Verify`, `kms:GetPublicKey` on the KMS key ARN |

### Follow-ups / Known Gaps

Items deferred from this implementation. None of these are stubs or partial work — they don't exist yet.

| Item | Reason deferred |
|------|----------------|
| Lambda authorizer scan | Authorizer code (`infra/envs/poc/lambdas/authorizer/`) excluded from all scan paths — different deployment lifecycle, no container image |
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
