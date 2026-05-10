# Max Weather — DevOps Assessment Implementation Plan

## TL;DR

> **Quick Summary**: Implement the Max Weather DevOps assessment (101 Digital): a Node.js weather-proxy on AWS EKS, fronted by API Gateway + Lambda Authorizer (Cognito OAuth2), with NGINX Ingress, Jenkins CI/CD, CloudWatch logging, and modular Terraform — delivered in three sequenced phases: **drawio diagram → Terraform infra → app + CI/CD**.
>
> **Deliverables** (D1–D6 from PDF):
> - D1: Architecture diagram (`docs/architecture.drawio`, exported PNG)
> - D2: Modular Terraform under `infra/` — bootstrap, modules, envs/staging
> - D3: K8s manifests — Deployment, Service, NGINX Ingress Controller (Helm), Ingress
> - D4: Jenkinsfile (declarative pipeline) + ci/ scripts
> - D5: API Gateway REST API (manual setup runbook + Lambda authorizer wired)
> - D6: Postman collection + environment template (verified via `newman`)
> - Bonus: Makefile task runner, evidence collection, teardown script
>
> **Estimated Effort**: Large (5–7 working days for one engineer)
> **Parallel Execution**: YES — 9 waves with parallel-friendly task splits
> **Critical Path**: W0 (gitignore) → W1 (bootstrap) → W2 (network+EKS) → W4 (deploy) → W5 (API GW) → W6 (evidence) → W8 (teardown)

---

## Context

### Original Request
User wants a work plan that, when executed by Sisyphus, will:
1. **First**: produce an architecture diagram via the drawio skill (soft checkpoint — present and continue)
2. **Then**: write Terraform infrastructure code
3. **Finally**: implement the app + CI/CD

### Interview Summary
**Confirmed decisions**:
- Cloud: **AWS** (us-east-1)
- App language: **Node.js (Express)** — same runtime as Lambda authorizer for consistency
- OAuth2 IdP: **Amazon Cognito User Pool** with `client_credentials` grant + resource server + custom scopes
- Container orchestration: **EKS 1.30**, managed node group (t3.medium, 2–10 nodes), 3 AZs
- Ingress: **NGINX Ingress Controller** (Helm chart `4.11.x`), exposed via **NLB** (internet-facing)
- CI/CD: **Jenkins on EC2 (t3.medium)** with IAM instance profile (no static AWS keys)
- Image registry: **ECR** with lifecycle policy (expire untagged after 7 days, keep last 10 tagged)
- Logging: **Fluent Bit DaemonSet** → CloudWatch Logs via IRSA
- Terraform state: **S3 + DynamoDB** (bootstrap module)
- Cleanup: **cloud-nuke** (already in workspace) wrapped with account-ID assertion
- Diagram review: **Soft checkpoint** — Sisyphus presents diagram in W1 then continues
- Budget: **>$30 OK** — multi-AZ NAT, full HA architecture
- Demo format: **Code only** — implement, capture evidence, teardown; user handles email submission
- Weather API: **Open-Meteo** (free, no auth needed)
- Repo: **Public** — strict gitignore + pre-commit secret-scan
- Environments: **2 namespaces** (`weather-staging`, `weather-prod`) in 1 EKS cluster
- Plan review: **High accuracy** with Momus loop until OKAY
- Output language: **English** for all repo deliverables (README, code, commits, evidence). Internal `.sisyphus/` planning files may stay in any language.

### Research Findings (from architecture-analysis doc + Metis review)
- Workspace already has `.gitignore` covering `app/`, `lambda-authorizer/`, `*.tfstate`, `terraform.tfvars`, `kubeconfig*` — but **MISSING** `cloud-nuke*` and `*.zip` → must be added in W0
- 4 Terraform skills installed: `refactor-module`, `terraform-search-import`, `terraform-stacks`, `terraform-style-guide` → use `terraform-style-guide` for HCL conformance; do NOT use `terraform-stacks` (HCP Stacks is out of scope)
- `cloud-nuke v0.50.0` binary is 282 MB — must NOT be committed
- PDF allows manual API Gateway setup — plan treats it as required (manual + runbook) with bonus stretch goal of partial Terraformization (≤2h time-box)

### Metis Review Highlights (gaps addressed)
- **Cost watchdog**: every cloud-resource wave includes a `cost-check` task before proceeding
- **Wave 2 long-pole**: EKS apply takes 15–20 min → Wave 3 (file authoring) runs in parallel during the wait
- **Lambda authorizer chicken-and-egg**: Wave 2 Terraform creates Lambda with placeholder code; Wave 4 deploys real code via `aws lambda update-function-code`
- **NGINX-created NLB not in Terraform state**: teardown order enforced (W8: helm uninstall → kubectl delete → terraform destroy → cloud-nuke)
- **API Gateway manual setup**: deliverable as numbered runbook + screenshots + reproducibility check
- **Postman OAuth2 setup**: Cognito needs resource server with custom scope `weather/read`; Postman uses `client_credentials` against `https://<domain>.auth.<region>.amazoncognito.com/oauth2/token`
- **HPA needs metrics-server**: explicit install task before evidence collection
- **TLS strategy**: terminate at API Gateway (free HTTPS); internal NLB→NGINX→pods is HTTP for demo simplicity (documented trade-off)
- **EKS API endpoint**: public but restricted to user's IP CIDR (not 0.0.0.0/0)
- **Multi-arch Docker**: pin `--platform linux/amd64` in build script (covers M-series Mac dev machines)

---

## Work Objectives

### Core Objective
Deliver a **public-repo, modular, production-ready** AWS infrastructure + Node.js weather-proxy app + Jenkins CI/CD that satisfies all 6 PDF deliverables, with executable evidence proving CloudWatch logging and HPA scaling work end-to-end.

### Concrete Deliverables
- `docs/architecture.drawio` + `docs/architecture.png` (D1)
- `infra/bootstrap/`, `infra/modules/{network,eks,ecr,cognito,lambda-authorizer,cloudwatch,jenkins,iam}/`, `infra/envs/staging/` (D2)
- `k8s/deployment.yaml`, `k8s/service.yaml`, `k8s/ingress.yaml`, `k8s/nginx-controller/values.yaml` (D3)
- `Jenkinsfile`, `ci/build.sh`, `ci/deploy.sh`, `ci/test.sh` (D4)
- `docs/api-gateway-runbook.md` + screenshots in `docs/evidence/05-api-gateway/` (D5)
- `docs/postman/max-weather.postman_collection.json` + `docs/postman/staging.postman_environment.template.json` (D6)
- `app/` (Node.js Express weather-proxy, ≤200 LOC), `lambda-authorizer/` (≤150 LOC)
- `Makefile` (top-level task runner)
- `README.md` (English, sections: Architecture, Setup, Deploy, Demo, Teardown, Assumptions, Cost Optimizations)
- `docs/evidence/{01-terraform,02-eks-nodes,03-cloudwatch-logs,04-hpa-scaling,05-api-gateway,06-postman,07-jenkins,08-jenkins}/`
- `scripts/teardown.sh` (cloud-nuke wrapper with account-ID assertion)

### Definition of Done
- [ ] `terraform validate` and `terraform fmt -check -recursive` pass for all modules and envs
- [ ] All 6 PDF deliverables present and verifiable by automated commands
- [ ] CloudWatch logs evidence: `aws logs filter-log-events --log-group-name /aws/eks/max-weather/application --start-time $(date -d '5 min ago' +%s)000 | jq '.events | length'` returns `> 0`
- [ ] HPA scaling evidence: `kubectl get hpa weather-api -n weather-prod -o json | jq '.status.currentReplicas'` returns `> 3` after load test
- [ ] API Gateway end-to-end smoke test: `curl -sf -H "Authorization: Bearer $TOKEN" "$API_URL/weather?latitude=21.03&longitude=105.85"` returns valid weather JSON
- [ ] Unauthorized request: `curl -s -o /dev/null -w "%{http_code}" "$API_URL/weather"` returns `401`
- [ ] Postman demo: `newman run docs/postman/max-weather.postman_collection.json -e docs/postman/staging.postman_environment.json` exits with code `0`
- [ ] Repo public, no secrets committed (verified via `gitleaks detect --source . --no-banner`)
- [ ] All infra torn down: `aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text` returns empty in target region
- [ ] All evidence files exist under `docs/evidence/`

### Must Have
- 24/7 HA via multi-AZ EKS, multi-AZ NLB, ≥3 replicas, PodDisruptionBudget
- HPA (CPU 60%) + Cluster Autoscaler
- OAuth2 via Cognito + custom Lambda authorizer (mandatory per PDF)
- All app + Lambda + API GW logs flowing to CloudWatch
- Modular Terraform parameterized via `tfvars` (no hardcoded region/account in modules)
- Jenkins pipeline: build → test → push ECR → deploy staging → integration test → manual approval → deploy prod
- Public repo with NO secrets leaked

### Must NOT Have (Hard Guardrails)
- ❌ Real weather backend (proxy to Open-Meteo only — app is ≤200 LOC)
- ❌ Frontend / web UI
- ❌ Custom domain / Route 53 / ACM certs (use API GW default URL)
- ❌ Multi-region or multi-account deployment
- ❌ Karpenter (use Cluster Autoscaler)
- ❌ Service mesh (Istio, Linkerd)
- ❌ Observability beyond CloudWatch (no Prometheus, Grafana, Datadog, X-Ray)
- ❌ Terraform Stacks / HCP Terraform (classic Terraform + S3 backend only)
- ❌ Hardcoded region, account ID, or AZ in `infra/modules/*` (only allowed in `infra/envs/*/terraform.tfvars`)
- ❌ Committed: `cloud-nuke*` binary, `.env`, `*.tfvars` (except `*.template`), `kubeconfig*`, `*.zip`, Postman environment with real secrets
- ❌ EKS API endpoint open to `0.0.0.0/0` (restrict to user IP)
- ❌ Static AWS access keys in Jenkins credential store (use IAM instance profile)
- ❌ AWS provider or Terraform version unpinned
- ❌ Vietnamese in repo deliverables (English only for README, code comments, commit messages)

---

## Verification Strategy (MANDATORY)

> **ZERO HUMAN INTERVENTION** — every acceptance criterion is agent-executable.

### Test Decision
- **Infrastructure exists**: NO (greenfield)
- **Automated tests**:
  - **App**: minimal — single integration test using `supertest` (proves Jenkins test stage works)
  - **Lambda authorizer**: minimal unit test using `jest` (JWT validation happy + sad path)
  - **Terraform**: `terraform validate` + `terraform plan` evidence capture (no Terratest — out of scope time-box)
- **Framework**: `bun test` for app + lambda (matches modern Node.js workflow); fall back to `npm test` if Bun unavailable
- **TDD**: NO — write tests alongside implementation in same task (avoid blocking on RED phase for greenfield app)

### QA Policy
Every task MUST include agent-executed QA scenarios. Evidence saved to `.sisyphus/evidence/task-{N}-{scenario-slug}.{ext}` AND mirrored to `docs/evidence/` for repo deliverable.

- **Frontend/UI**: N/A (no frontend in scope)
- **TUI/CLI**: `interactive_bash` (tmux) for `terraform apply`, `kubectl`, `helm`, `aws cli` verification
- **API/Backend**: `Bash` with `curl` for API Gateway, `newman` for Postman collection
- **Library/Module**: `Bash` with `node`/`bun` for unit tests
- **Diagrams**: file-existence + format check (`file docs/architecture.png | grep PNG`)

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 0 (Pre-flight, sequential, ~5 min):
└── Task 1: Repo hygiene — gitignore patches + pre-commit hooks + Makefile skeleton

Wave 1 (Architecture diagram, soft checkpoint, ~30 min):
└── Task 2: Generate drawio architecture diagram + export PNG

Wave 2 (Bootstrap state backend, sequential, ~5 min):
└── Task 3: Bootstrap S3 bucket + DynamoDB lock table for Terraform state

Wave 3 (Foundation Terraform modules — file-authoring parallel, ~2-3 h):
├── Task 4:  Module - network (VPC, subnets, IGW, NAT, route tables)
├── Task 5:  Module - iam (cross-cutting roles: Jenkins, IRSA helpers)
├── Task 6:  Module - ecr (repo + lifecycle policy)
├── Task 7:  Module - cognito (User Pool, App Client, Resource Server, Domain)
├── Task 8:  Module - cloudwatch (log groups, metric filters, alarms, SNS topic)
└── Task 9:  Module - lambda-authorizer (Lambda function with placeholder code, IAM)

Wave 4 (Compute + CI infra Terraform — depends on Wave 3, parallel, ~3-4 h):
├── Task 10: Module - eks (cluster, node group, OIDC provider, addons, IRSA roles)
├── Task 11: Module - jenkins (EC2, SG, IAM instance profile, user-data)
└── Task 12: envs/staging compose root (calls all modules with tfvars)

Wave 5 (Long-pole apply + parallel file authoring, ~30 min):
├── Task 13: terraform apply (network + EKS + ECR + Cognito + CloudWatch + Lambda placeholder + Jenkins + IAM) — runs ~20 min in background
├── Task 14: App code — Node.js Express weather-proxy (src + Dockerfile + minimal test)
├── Task 15: Lambda authorizer code — JWT verify + JWKs cache + tests
├── Task 16: K8s manifests — Deployment, Service, Ingress YAMLs
├── Task 17: NGINX Ingress Controller Helm values + install script
├── Task 18: Jenkinsfile + ci/ helper scripts
└── Task 19: Postman collection + environment template

Wave 6 (Cluster bootstrap + deploy — depends on W5 apply, sequential ~30 min):
├── Task 20: Configure kubectl, install metrics-server + Cluster Autoscaler + Fluent Bit + NGINX Ingress
├── Task 21: Build & push Docker image to ECR; deploy app to staging + prod namespaces
└── Task 22: Update Lambda authorizer with real code; smoke-test `curl <NLB-DNS>`

Wave 7 (API Gateway manual setup + Postman demo, ~1 h):
├── Task 23: API Gateway runbook execution (manual config) + screenshots
└── Task 24: Postman demo via newman; capture evidence

Wave 8 (Evidence collection — depends on W7, parallel ~1-2 h):
├── Task 25: Load test (hey/k6) → HPA + Cluster Autoscaler scaling evidence
├── Task 26: CloudWatch logs evidence (app, Lambda, API GW access)
├── Task 27: Cost watchdog snapshot (`aws ce get-cost-and-usage`, instance audit)
├── Task 28: README authoring + final repo polish
└── Task 29: Jenkins pipeline end-to-end run + evidence

Wave 9 (Teardown, sequential, ~30 min):
├── Task 30: Helm uninstall + kubectl delete (drains NGINX-created NLB)
├── Task 31: terraform destroy on envs/staging
└── Task 32: cloud-nuke region scope with account-ID assertion + post-teardown cost audit

Wave FINAL (Verification — 4 parallel reviews, then user okay):
├── Task F1: Plan compliance audit (oracle)
├── Task F2: Code quality + security review (unspecified-high)
├── Task F3: Cost + teardown verification (unspecified-high)
└── Task F4: Scope fidelity check (deep)
→ Present results → Get explicit user okay → mark plan complete

Critical Path: 1 → 2 → 3 → 4 → 10 → 12 → 13 → 20 → 21 → 22 → 23 → 25 → 30 → 32 → F1-F4 → user okay
Parallel Speedup: ~50% vs sequential (Wave 3 + Wave 5 are the major parallel windows)
Max Concurrent: 6 (Wave 3) and 7 (Wave 5)
```

### Dependency Matrix (abbreviated)

- **1**: — → 2, 3, all subsequent
- **2**: 1 → (independent, soft checkpoint)
- **3**: 1 → 4-12
- **4-9**: 3 → 12
- **10**: 3, 4, 5 → 12, 13
- **11**: 3, 4, 5 → 12, 13
- **12**: 4-11 → 13
- **13**: 12 → 20, 21, 22 (long-pole, ~20 min)
- **14-19**: 1 (independent file authoring; can run during 13)
- **20**: 13 → 21, 25, 26
- **21**: 13, 14, 16, 17, 20 → 22, 25
- **22**: 13, 15, 21 → 23
- **23**: 22 → 24, 25
- **24**: 23 → 26
- **25-29**: 22, 23, 24 → 30
- **30**: 25-29 → 31
- **31**: 30 → 32
- **32**: 31 → F1-F4

### Agent Dispatch Summary

- **Wave 0**: T1 → `quick`
- **Wave 1**: T2 → `unspecified-high` + `drawio` skill
- **Wave 2**: T3 → `unspecified-high`
- **Wave 3**: T4-T9 → `unspecified-high` + `terraform-style-guide` skill
- **Wave 4**: T10-T12 → `unspecified-high` + `terraform-style-guide` skill
- **Wave 5**: T13 → `unspecified-high`; T14, T15 → `unspecified-high`; T16, T17 → `unspecified-high`; T18 → `unspecified-high`; T19 → `quick`
- **Wave 6**: T20-T22 → `unspecified-high`
- **Wave 7**: T23 → `unspecified-high`; T24 → `quick`
- **Wave 8**: T25-T26 → `unspecified-high`; T27 → `quick`; T28 → `writing`; T29 → `unspecified-high`
- **Wave 9**: T30-T32 → `unspecified-high`
- **Final**: F1 → `oracle`; F2 → `unspecified-high`; F3 → `unspecified-high`; F4 → `deep`

---

## TODOs

- [x] 1. **Repo hygiene: gitignore patches + pre-commit hooks + Makefile skeleton**

  **What to do**:
  - Append to existing `.gitignore`: `cloud-nuke*`, `*.zip` (if not already), `*.tar.gz`, `docs/postman/*.postman_environment.json` (allow `*.template.json`), `docs/evidence/**/*.pem`, `node_modules/`, `coverage/`, `.terraform.lock.hcl` (KEEP this — needs commit; remove from gitignore if present)
  - Create `.pre-commit-config.yaml` with hooks: `gitleaks` (scan staged), `terraform_fmt`, `terraform_validate`, `end-of-file-fixer`, `trailing-whitespace`
  - Install pre-commit: `pip install --break-system-packages pre-commit && pre-commit install` (or use `pipx`)
  - Create skeleton `Makefile` at repo root with targets: `help`, `init`, `plan`, `apply`, `destroy`, `build`, `push`, `deploy-staging`, `deploy-prod`, `test`, `evidence`, `nuke`. Each target prints "TODO: implement" until populated in later waves.
  - Create empty directories with `.gitkeep`: `infra/bootstrap/`, `infra/modules/`, `infra/envs/staging/`, `app/`, `lambda-authorizer/`, `k8s/`, `ci/`, `scripts/`, `docs/evidence/{01-terraform,02-eks-nodes,03-cloudwatch-logs,04-hpa-scaling,05-api-gateway,06-postman,07-jenkins,08-jenkins}/`, `docs/postman/`

  **Must NOT do**:
  - Do NOT commit any actual secrets / API keys / AWS account IDs
  - Do NOT add `.terraform.lock.hcl` to gitignore (it MUST be committed for reproducible builds)
  - Do NOT install pre-commit globally with sudo

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Pure file authoring, no logic, no AWS calls. Trivial scope.
  - **Skills**: []
    - No skills needed — just file edits.

  **Parallelization**:
  - **Can Run In Parallel**: NO — must run first (Wave 0)
  - **Parallel Group**: Wave 0
  - **Blocks**: All subsequent tasks (sets up repo hygiene)
  - **Blocked By**: None

  **References**:
  - **Pattern References**:
    - Existing `.gitignore` at workspace root — extend, do not replace
    - `cloud-nuke` binary at `/home/ubuntu/Workspace/assessment/cloud-nuke_linux_amd64` (282 MB) is what must NOT be committed
  - **External References**:
    - pre-commit hooks for Terraform: `https://github.com/antonbabenko/pre-commit-terraform`
    - gitleaks: `https://github.com/gitleaks/gitleaks`
  - **WHY Each Reference Matters**:
    - cloud-nuke binary at 282 MB will balloon repo and fail GitHub push limits — exclusion is critical
    - pre-commit-terraform provides `terraform_fmt`, `terraform_validate`, `tflint` hooks — saves manual setup

  **Acceptance Criteria**:
  - [ ] `git check-ignore cloud-nuke_linux_amd64` returns the file (proves it's ignored)
  - [ ] `test -f .pre-commit-config.yaml`
  - [ ] `pre-commit run --all-files` exits 0 (or skips if files don't exist yet)
  - [ ] `make help` lists all skeleton targets
  - [ ] `find docs/evidence infra/modules app lambda-authorizer k8s ci scripts -type d | wc -l` returns >= 13

  **QA Scenarios**:

  ```
  Scenario: Verify cloud-nuke binary excluded from git
    Tool: Bash
    Preconditions: Workspace root, cloud-nuke binary present at root
    Steps:
      1. Run `git check-ignore -v cloud-nuke_linux_amd64`
      2. Assert exit code is 0 and stdout matches `.gitignore:.*cloud-nuke`
      3. Run `git status --porcelain | grep cloud-nuke || echo CLEAN`
      4. Assert output is exactly "CLEAN"
    Expected Result: cloud-nuke binary recognized as ignored, not in working tree
    Failure Indicators: git check-ignore exits non-zero, or git status shows cloud-nuke as untracked
    Evidence: .sisyphus/evidence/task-01-gitignore-check.txt

  Scenario: Pre-commit hooks block secret leak
    Tool: Bash
    Preconditions: pre-commit installed and config present
    Steps:
      1. Create temp file `/tmp/test-secret.tf` with `aws_access_key = "AKIAIOSFODNN7EXAMPLE"`
      2. Copy to repo `cp /tmp/test-secret.tf ./test-secret.tf && git add ./test-secret.tf`
      3. Run `pre-commit run --files ./test-secret.tf 2>&1 | tee /tmp/precommit-out.txt`
      4. Assert grep -q "gitleaks" /tmp/precommit-out.txt (gitleaks ran)
      5. Assert grep -qE "leak|secret|finding" /tmp/precommit-out.txt (gitleaks detected)
      6. Cleanup: `git reset HEAD ./test-secret.tf && rm ./test-secret.tf`
    Expected Result: gitleaks detects the dummy AWS key and pre-commit fails
    Failure Indicators: gitleaks not invoked, or finding not detected
    Evidence: .sisyphus/evidence/task-01-precommit-blocks-secret.txt

  Scenario: Makefile help target works
    Tool: Bash
    Steps:
      1. Run `make help`
      2. Assert exit 0
      3. Assert stdout contains all of: init, plan, apply, destroy, build, push, deploy-staging, deploy-prod, test, evidence, nuke
    Expected Result: Help output lists ≥11 documented targets
    Evidence: .sisyphus/evidence/task-01-makefile-help.txt
  ```

  **Evidence to Capture**:
  - [ ] task-01-gitignore-check.txt — output of `git check-ignore` and `git ls-files`
  - [ ] task-01-precommit-blocks-secret.txt — pre-commit output blocking dummy key
  - [ ] task-01-makefile-help.txt — make help output

  **Commit**: YES (single commit)
  - Message: `chore: gitignore patches, pre-commit hooks, makefile skeleton`
  - Files: `.gitignore`, `.pre-commit-config.yaml`, `Makefile`, `**/.gitkeep`
  - Pre-commit: `pre-commit run --all-files` (must pass)

- [x] 2. **Generate architecture diagram via drawio skill (soft checkpoint)**

  **What to do**:
  - Use `drawio` skill to generate `docs/architecture.drawio`
  - The diagram MUST include all components from `.sisyphus/plans/max-weather-architecture-analysis.md` §4.1 Component Inventory:
    - Edge: Client (Postman/Frontend), Route 53 (optional), API Gateway REST, Lambda Authorizer, Cognito User Pool
    - Network: VPC (3 AZ), public subnets (NLB, NAT GW, Jenkins EC2), private subnets (EKS workers)
    - EKS: Cluster control plane, managed node group, namespaces (weather-staging, weather-prod), each with NGINX Ingress pods, Ingress, Service, Deployment, HPA
    - Cluster add-ons label: Cluster Autoscaler, Fluent Bit, AWS LB Controller, External Secrets, CoreDNS, VPC CNI, metrics-server
    - AWS services: ECR, CloudWatch Logs, CloudWatch Alarms, Secrets Manager, IAM, S3+DynamoDB (tfstate)
    - External: GitHub repo, Public Weather API (Open-Meteo)
  - Use proper containers (swimlane) for VPC, public subnets, private subnets, EKS cluster, namespaces, AWS services
  - Use AWS color palette: orange #FF9900 (compute/CI), blue #3334B9 (storage/registry), pink/red #DD344C / #FF4F8B (security/auth), green #7AA116 (network), purple #8C4FFF (LB), magenta #CC2264 (logs/alarms)
  - Number the request lifecycle edges (1–10) per `.sisyphus/plans/max-weather-architecture-analysis.md` §4.3
  - Add a title at top: "Max Weather - AWS Production Architecture (HA, Auto-scale, OAuth2, CI/CD)"
  - Add a legend at bottom describing color coding
  - Export to PNG using `drawio -x -f png -e -b 10 -o docs/architecture.png docs/architecture.drawio`
  - Keep BOTH the .drawio (editable) AND .png (preview) — do NOT delete .drawio (deviates from skill default; we want both committed)
  - Commit and **inform user** with a short summary of what's in the diagram, but DO NOT WAIT — continue to next wave (soft checkpoint per user request)

  **Must NOT do**:
  - Do NOT delete the .drawio source file
  - Do NOT create multiple diagrams (one comprehensive diagram is the deliverable)
  - Do NOT use the Mermaid diagram from architecture-analysis.md as the deliverable (need real drawio file)
  - Do NOT include components not in scope (no Karpenter, no Istio, no Prometheus, no custom domain)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Requires careful XML authoring, color/layout decisions, and skill invocation. Visual quality matters for D1.
  - **Skills**: [`drawio`]
    - `drawio`: REQUIRED — provides XML format reference, CLI invocation patterns, container/layout best practices.

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Wave 0 once it completes; non-blocking for subsequent waves per user "soft checkpoint" decision)
  - **Parallel Group**: Wave 1 (alone)
  - **Blocks**: None (soft checkpoint)
  - **Blocked By**: Task 1 (needs `docs/` dirs)

  **References**:
  - **Pattern References**:
    - `.sisyphus/plans/max-weather-architecture-analysis.md` §4.1, §4.2, §4.3 — component inventory, Mermaid diagram, request lifecycle
    - drawio skill at `/home/ubuntu/.agents/skills/drawio/SKILL.md` — XML format, CLI flags, container patterns
  - **External References**:
    - draw.io style reference: `https://www.drawio.com/doc/faq/drawio-style-reference.html`
    - AWS shape library naming: `shape=mxgraph.aws4.<resource>` (e.g., `shape=mxgraph.aws4.client`, `shape=mxgraph.aws4.ec2`)
  - **WHY Each Reference Matters**:
    - Architecture analysis doc is the source of truth for what to depict — do not invent new components
    - drawio skill explains why .drawio + PNG (embedded XML) is the right format
    - AWS shapes lend visual recognition; reviewers familiar with AWS will instantly grok components

  **Acceptance Criteria**:
  - [ ] `test -f docs/architecture.drawio` and file is well-formed XML (`xmllint --noout docs/architecture.drawio`)
  - [ ] `test -f docs/architecture.png` and `file docs/architecture.png | grep -q PNG`
  - [ ] PNG file size > 50 KB (proves non-trivial content)
  - [ ] grep -E "API Gateway|Cognito|EKS|NGINX|Jenkins|ECR|CloudWatch|VPC" docs/architecture.drawio | wc -l returns >= 8 (all key components labeled)
  - [ ] No forbidden components: `grep -iE "karpenter|istio|linkerd|prometheus|grafana|datadog|route53.*custom" docs/architecture.drawio | wc -l` returns 0

  **QA Scenarios**:

  ```
  Scenario: Diagram XML is well-formed and contains all required components
    Tool: Bash
    Preconditions: docs/architecture.drawio created
    Steps:
      1. Run `xmllint --noout docs/architecture.drawio` — assert exit 0 (well-formed XML)
      2. Run `grep -oE "value=\"[^\"]+\"" docs/architecture.drawio | sort -u > /tmp/diagram-labels.txt`
      3. For each required label (API Gateway, Lambda Authorizer, Cognito, NGINX Ingress, Service, Deployment, HPA, ECR, CloudWatch, Jenkins, NLB, VPC, EKS), assert `grep -qiE "<label>" /tmp/diagram-labels.txt`
      4. Save labels list as evidence
    Expected Result: All 13 required component labels present
    Failure Indicators: xmllint reports parse error; any required label missing
    Evidence: .sisyphus/evidence/task-02-diagram-labels.txt + docs/architecture.drawio + docs/architecture.png

  Scenario: PNG renders successfully via drawio CLI
    Tool: Bash
    Steps:
      1. Run `drawio -x -f png -e -b 10 -o /tmp/diagram-test.png docs/architecture.drawio 2>&1 | tee /tmp/drawio-export.log`
      2. Assert exit 0
      3. Assert `file /tmp/diagram-test.png | grep -q "PNG image data"`
      4. Assert PNG dimensions sane: `identify -format "%wx%h" /tmp/diagram-test.png` returns dimensions where width >= 800 and height >= 400
    Expected Result: PNG export succeeds, file is valid PNG with reasonable dimensions
    Failure Indicators: drawio CLI errors, file not PNG, dimensions absurdly small
    Evidence: .sisyphus/evidence/task-02-png-export.log + docs/architecture.png

  Scenario: Forbidden components not in diagram (scope guardrail)
    Tool: Bash
    Steps:
      1. Run `grep -ciE "karpenter|istio|linkerd|prometheus|grafana|datadog" docs/architecture.drawio`
      2. Assert output is exactly "0"
    Expected Result: No out-of-scope components polluting the diagram
    Evidence: .sisyphus/evidence/task-02-no-forbidden.txt
  ```

  **Evidence to Capture**:
  - [ ] task-02-diagram-labels.txt — sorted list of labels in diagram
  - [ ] task-02-png-export.log — drawio CLI output
  - [ ] task-02-no-forbidden.txt — guardrail check
  - [ ] docs/architecture.drawio (committed to repo)
  - [ ] docs/architecture.png (committed to repo)

  **Commit**: YES (single commit)
  - Message: `docs(architecture): add system architecture diagram (drawio + png)`
  - Files: `docs/architecture.drawio`, `docs/architecture.png`
  - Pre-commit: `pre-commit run --files docs/architecture.drawio` (xml-fmt may rewrite — accept rewrite then commit)

- [x] 3. **Bootstrap S3 + DynamoDB for Terraform state**

  **What to do**:
  - Create `infra/bootstrap/main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `terraform.tfvars.example`
  - Use **local backend** (no `backend "s3"` block) — this is the chicken-and-egg breaker
  - Resources:
    - `aws_s3_bucket.tfstate` with: versioning enabled, server-side encryption (AES256), public access block (all 4 settings true), `force_destroy = false`
    - `aws_s3_bucket_lifecycle_configuration` to expire noncurrent versions after 90 days
    - `aws_dynamodb_table.tflock` with: `LockID` partition key (string), billing mode `PAY_PER_REQUEST`
    - `aws_iam_policy.tfstate_access` for Jenkins/operator role (output only — attached in iam module later)
  - Variables: `region`, `bucket_name` (default: `max-weather-tfstate-${random_id}`), `dynamodb_table_name` (default: `max-weather-tflock`), `tags`
  - Outputs: `tfstate_bucket_name`, `tfstate_bucket_arn`, `tflock_table_name`, `tflock_table_arn`
  - Versions: `terraform >= 1.9, < 2.0`, `aws ~> 5.60`, `random ~> 3.6`
  - Apply: `cd infra/bootstrap && terraform init && terraform apply -auto-approve`
  - Capture outputs to `.sisyphus/evidence/task-03-bootstrap-outputs.json` AND `docs/evidence/01-terraform/bootstrap-outputs.json`

  **Must NOT do**:
  - Do NOT use `backend "s3"` in this module (chicken-and-egg)
  - Do NOT enable bucket public access (must be private with all 4 block settings)
  - Do NOT skip versioning or encryption
  - Do NOT hardcode bucket names — use `random_id` suffix for global uniqueness
  - Do NOT commit `terraform.tfvars` (only `.example`)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Greenfield Terraform module with security-sensitive defaults; needs `terraform-style-guide` skill compliance.
  - **Skills**: [`terraform-style-guide`]
    - `terraform-style-guide`: REQUIRED — ensures HCL conformance (file naming, variable docs, output docs, no nested ternaries, etc.)

  **Parallelization**:
  - **Can Run In Parallel**: NO (sequential — must finish before W3 starts)
  - **Parallel Group**: Wave 2 (alone)
  - **Blocks**: All Wave 3+ tasks (they need state backend)
  - **Blocked By**: Task 1

  **References**:
  - **Pattern References**:
    - `terraform-style-guide` skill at `/home/ubuntu/.agents/skills/terraform-style-guide/SKILL.md`
    - `.sisyphus/plans/max-weather-architecture-analysis.md` §4.4 (Terraform module map)
  - **External References**:
    - AWS S3 best practices for tfstate: `https://developer.hashicorp.com/terraform/language/backend/s3`
    - DynamoDB lock table schema (LockID PK only): same source
  - **WHY Each Reference Matters**:
    - terraform-style-guide enforces HCL conventions reviewers expect (matches HashiCorp norms)
    - The S3 backend docs specify exact DynamoDB schema — must match or locking silently fails

  **Acceptance Criteria**:
  - [ ] `cd infra/bootstrap && terraform init && terraform validate` exits 0
  - [ ] `terraform fmt -check` exits 0
  - [ ] `terraform apply -auto-approve` succeeds (or `-target=` if too coarse)
  - [ ] `aws s3api get-bucket-versioning --bucket $(terraform output -raw tfstate_bucket_name)` shows `Status: Enabled`
  - [ ] `aws s3api get-public-access-block --bucket $(terraform output -raw tfstate_bucket_name)` shows all 4 settings true
  - [ ] `aws s3api get-bucket-encryption --bucket $(terraform output -raw tfstate_bucket_name)` shows AES256
  - [ ] `aws dynamodb describe-table --table-name $(terraform output -raw tflock_table_name)` returns table with `LockID` HASH key

  **QA Scenarios**:

  ```
  Scenario: Bootstrap creates secure S3 + DynamoDB
    Tool: interactive_bash (tmux)
    Preconditions: AWS credentials configured, region us-east-1
    Steps:
      1. tmux: `cd infra/bootstrap && terraform init 2>&1 | tee /tmp/tf-init.log`
      2. tmux: `terraform validate && terraform fmt -check`
      3. tmux: `terraform apply -auto-approve 2>&1 | tee /tmp/tf-apply.log`
      4. tmux: `BUCKET=$(terraform output -raw tfstate_bucket_name); TABLE=$(terraform output -raw tflock_table_name)`
      5. tmux: `aws s3api get-bucket-versioning --bucket "$BUCKET" --query Status --output text` → assert "Enabled"
      6. tmux: `aws s3api get-public-access-block --bucket "$BUCKET" --query 'PublicAccessBlockConfiguration' --output json` → assert all four true via jq
      7. tmux: `aws s3api get-bucket-encryption --bucket "$BUCKET" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text` → assert "AES256"
      8. tmux: `aws dynamodb describe-table --table-name "$TABLE" --query 'Table.KeySchema[0].AttributeName' --output text` → assert "LockID"
      9. Save outputs JSON: `terraform output -json > docs/evidence/01-terraform/bootstrap-outputs.json`
    Expected Result: Bucket exists with versioning + encryption + public-access-block; DynamoDB table has correct schema
    Failure Indicators: any aws cli call returns wrong value or non-zero exit
    Evidence: docs/evidence/01-terraform/bootstrap-outputs.json + .sisyphus/evidence/task-03-validation.txt

  Scenario: Re-running apply is idempotent
    Tool: interactive_bash
    Steps:
      1. tmux: `cd infra/bootstrap && terraform apply -auto-approve 2>&1 | tee /tmp/tf-rerun.log`
      2. Assert: `grep -q "No changes" /tmp/tf-rerun.log`
    Expected Result: Second apply is a no-op (proves config is stable)
    Evidence: .sisyphus/evidence/task-03-idempotent.txt
  ```

  **Evidence to Capture**:
  - [ ] task-03-validation.txt — all aws cli verification outputs
  - [ ] task-03-idempotent.txt — second-apply no-changes proof
  - [ ] docs/evidence/01-terraform/bootstrap-outputs.json — terraform outputs

  **Commit**: YES (single commit)
  - Message: `feat(infra/bootstrap): s3 + dynamodb for terraform remote state`
  - Files: `infra/bootstrap/{main.tf,variables.tf,outputs.tf,versions.tf,terraform.tfvars.example,README.md}`
  - Pre-commit: `terraform_fmt`, `terraform_validate`, `gitleaks`

- [x] 4. **Networking module: VPC, subnets (3 AZs), NAT, IGW, routing, endpoints**

  **What to do**:
  - Create `infra/modules/networking/{main.tf,variables.tf,outputs.tf,versions.tf,README.md}`
  - Resources:
    - `aws_vpc` with `cidr_block = var.vpc_cidr` (default `10.20.0.0/16`), DNS support + hostnames enabled
    - 3 public subnets (`/24` each, one per AZ from `data.aws_availability_zones.available`) tagged `kubernetes.io/role/elb=1`
    - 3 private subnets (`/24` each, one per AZ) tagged `kubernetes.io/role/internal-elb=1` and `kubernetes.io/cluster/<cluster_name>=shared`
    - 1 IGW attached to VPC
    - 1 NAT gateway (single-AZ to save cost; documented trade-off in README) with EIP
    - Public route table with default route to IGW; associate all public subnets
    - Private route table with default route to NAT; associate all private subnets
    - VPC endpoints (gateway): S3, DynamoDB (free, save NAT bytes for tfstate)
    - Security group `eks_cluster_sg` (egress all; ingress added by EKS module)
  - Variables: `name`, `vpc_cidr`, `public_subnet_cidrs` (list, default 3 calculated via `cidrsubnet`), `private_subnet_cidrs` (list, default 3), `tags`, `cluster_name`
  - Outputs: `vpc_id`, `vpc_cidr_block`, `public_subnet_ids`, `private_subnet_ids`, `nat_gateway_ids`, `igw_id`
  - Use `for_each` over AZ list (NOT count) for subnets — easier to extend

  **Must NOT do**:
  - Do NOT use 3 NAT gateways (cost: ~$32/mo each); single NAT acceptable for assessment scope (documented)
  - Do NOT hardcode AZ names — use `data.aws_availability_zones`
  - Do NOT use `count` for subnets — use `for_each`
  - Do NOT skip the kubernetes.io subnet tags — load balancer controller needs them

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Foundational network module with multiple security-sensitive defaults (subnet tags, route tables); reused by all envs.
  - **Skills**: [`terraform-style-guide`]
    - `terraform-style-guide`: REQUIRED — module structure compliance.

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 3 group)
  - **Parallel Group**: Wave 3 — with T5, T6, T7, T8, T9
  - **Blocks**: T10 (EKS cluster needs VPC + subnets), T25 (Jenkins EC2 needs VPC + public subnet)
  - **Blocked By**: T3 (needs state backend)

  **References**:
  - **Pattern References**:
    - `terraform-style-guide` skill at `/home/ubuntu/.agents/skills/terraform-style-guide/SKILL.md`
    - `.sisyphus/plans/max-weather-architecture-analysis.md` §3 (VPC layout) and §4.4 (module map)
  - **External References**:
    - EKS subnet tagging requirements: `https://docs.aws.amazon.com/eks/latest/userguide/network-load-balancing.html#subnet-tagging-for-load-balancers`
    - VPC endpoint pricing (S3/DynamoDB gateway = free): `https://aws.amazon.com/privatelink/pricing/`
  - **WHY Each Reference Matters**:
    - EKS load balancer controller silently skips subnets without the `kubernetes.io/role/*` tags — production-blocking bug if missed
    - Gateway endpoints for S3/DynamoDB are free and save NAT bytes when Jenkins/EKS access tfstate

  **Acceptance Criteria**:
  - [ ] `terraform validate` and `terraform fmt -check` pass in `envs/staging` consuming this module
  - [ ] After apply: `aws ec2 describe-vpcs --filters Name=tag:Name,Values=max-weather-* --query 'Vpcs[0].CidrBlock' --output text` returns `10.20.0.0/16`
  - [ ] `aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC --query 'length(Subnets)'` returns `6`
  - [ ] Each public subnet has tag `kubernetes.io/role/elb=1`; each private subnet has `kubernetes.io/role/internal-elb=1`
  - [ ] 1 NAT gateway, 1 IGW present and routes wired correctly
  - [ ] S3 + DynamoDB gateway endpoints present (`aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$VPC --query 'VpcEndpoints[].ServiceName'`)

  **QA Scenarios**:

  ```
  Scenario: VPC + subnets created with correct tags
    Tool: interactive_bash
    Preconditions: T3 done; staging env consumes module
    Steps:
      1. tmux: `cd infra/envs/staging && terraform apply -target=module.networking -auto-approve 2>&1 | tee /tmp/tf-net.log`
      2. tmux: `VPC=$(terraform output -raw vpc_id)`
      3. tmux: `aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC --query 'Subnets[].Tags[?Key==`kubernetes.io/role/elb`].Value' --output json | tee /tmp/elb-tags.json`
      4. Assert: `jq 'flatten | map(select(.=="1")) | length' /tmp/elb-tags.json` returns `3`
      5. tmux: `aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC --query 'RouteTables[].Routes[?GatewayId!=null && starts_with(GatewayId, `igw-`)] | []' --output json` → assert non-empty
      6. tmux: `aws ec2 describe-nat-gateways --filter Name=vpc-id,Values=$VPC --query 'NatGateways[?State==`available`] | length(@)' --output text` → assert `1`
    Expected Result: 6 subnets (3 public + 3 private) with correct tags; IGW + NAT routing functional
    Failure Indicators: subnet count != 6, missing kubernetes.io tags, NAT not available
    Evidence: docs/evidence/01-terraform/networking-state.json + .sisyphus/evidence/task-04-validation.txt

  Scenario: VPC endpoints reduce NAT traffic
    Tool: Bash
    Steps:
      1. `aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$VPC --query 'VpcEndpoints[].ServiceName' --output json`
      2. Assert: includes `com.amazonaws.us-east-1.s3` AND `com.amazonaws.us-east-1.dynamodb`
    Expected Result: Both gateway endpoints present
    Evidence: .sisyphus/evidence/task-04-vpc-endpoints.json
  ```

  **Evidence to Capture**:
  - [ ] task-04-validation.txt — subnet/route/NAT verification outputs
  - [ ] task-04-vpc-endpoints.json — endpoint list
  - [ ] docs/evidence/01-terraform/networking-state.json — terraform state for module

  **Commit**: YES (single commit)
  - Message: `feat(infra/modules/networking): vpc with 3-az subnets, single nat, vpc endpoints`
  - Files: `infra/modules/networking/*`, `infra/envs/staging/networking.tf` (module call)
  - Pre-commit: `terraform_fmt`, `terraform_validate`, `gitleaks`

- [x] 5. **IAM module: roles + IRSA trust policies + Jenkins instance profile**

  **What to do**:
  - Create `infra/modules/iam/{main.tf,variables.tf,outputs.tf,versions.tf,README.md}`
  - Resources:
    - `aws_iam_role.eks_cluster` — trust `eks.amazonaws.com`, attach `AmazonEKSClusterPolicy`, `AmazonEKSVPCResourceController`
    - `aws_iam_role.eks_node` — trust `ec2.amazonaws.com`, attach `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`
    - `aws_iam_role.jenkins` (for EC2 instance profile) — trust `ec2.amazonaws.com`; inline policy: ECR push/pull, EKS describe/list, S3 tfstate (read+write), DynamoDB tflock (read+write+delete), Lambda update-function-code, CloudWatch Logs read
    - `aws_iam_instance_profile.jenkins`
    - **IRSA roles** (require OIDC provider ARN as input — output of EKS module, so this module exposes a sub-module or accepts `oidc_provider_arn` + `oidc_provider_url` as variables to be wired post-EKS):
      - `aws_iam_role.cluster_autoscaler` — IRSA trust for `kube-system:cluster-autoscaler`; policy: EC2 ASG describe/set-desired-capacity/terminate-instance
      - `aws_iam_role.fluent_bit` — IRSA for `amazon-cloudwatch:fluent-bit`; policy: CloudWatch Logs put-events + create-log-stream
      - `aws_iam_role.aws_lb_controller` — IRSA for `kube-system:aws-load-balancer-controller`; policy from official AWS doc (downloaded JSON)
      - `aws_iam_role.external_secrets` — IRSA for `external-secrets:external-secrets`; policy: Secrets Manager get-secret-value + describe-secret on `max-weather/*`
      - `aws_iam_role.weather_app_staging` and `aws_iam_role.weather_app_prod` — IRSA for `weather-staging:weather-api` and `weather-prod:weather-api`; minimal policy (CloudWatch Logs put-log-events on app log group)
      - `aws_iam_role.lambda_authorizer` — trust `lambda.amazonaws.com`; attach `AWSLambdaBasicExecutionRole`, inline policy: Cognito describe-user-pool-client + jwks fetch (none needed — Cognito JWKS is public)
  - Variables: `name_prefix`, `oidc_provider_arn` (string, optional/empty), `oidc_provider_url` (string, optional/empty), `tags`, `tfstate_bucket_arn`, `tflock_table_arn`
  - Outputs: all role ARNs by purpose; `jenkins_instance_profile_name`
  - Use `dynamic "statement"` blocks where helpful; download AWS LB controller policy JSON to `infra/modules/iam/policies/aws-lb-controller.json` (committed)

  **Must NOT do**:
  - Do NOT use `*` for resource ARNs in inline policies (least-privilege; scope to specific bucket/table/log-group ARNs)
  - Do NOT create users with static keys
  - Do NOT skip IRSA — node-role permissions are insecure for app pods

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Security-critical IAM with many least-privilege policies; mistakes cause silent prod incidents.
  - **Skills**: [`terraform-style-guide`]
    - `terraform-style-guide`: REQUIRED.

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 3 group, but IRSA roles APPLY in 2 sub-phases — see below)
  - **Parallel Group**: Wave 3 — with T4, T6, T7, T8, T9 (authoring is parallel; apply has 2 phases)
  - **Blocks**: T10 (EKS needs cluster role), T25 (Jenkins needs instance profile), T13–T19 (need IRSA role ARNs)
  - **Blocked By**: T3 (needs tfstate ARNs)
  - **Note**: IRSA roles depend on EKS OIDC provider — module accepts ARN as variable; on first apply, OIDC vars are empty (skip IRSA via `count`); after T10, re-run with OIDC ARN to create IRSA roles.

  **References**:
  - **Pattern References**:
    - `terraform-style-guide` skill
    - `.sisyphus/plans/max-weather-architecture-analysis.md` §4.4 (module map) and §6 (IAM/IRSA)
  - **External References**:
    - IRSA setup: `https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html`
    - AWS LB Controller IAM policy JSON: `https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.8.2/docs/install/iam_policy.json`
    - Cluster Autoscaler IAM: `https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md#iam-policy`
  - **WHY Each Reference Matters**:
    - IRSA trust policy syntax is unforgiving — wrong `sub` claim format = pods can't assume role
    - LB Controller policy must be exact version-matched JSON; subtle action drift breaks ALB provisioning
    - Cluster Autoscaler needs `autoscaling:SetDesiredCapacity` scoped to ASG with right tag — wrong scope = won't scale

  **Acceptance Criteria**:
  - [ ] `terraform validate` and `fmt -check` pass
  - [ ] After apply: `aws iam get-role --role-name max-weather-eks-cluster --query 'Role.AssumeRolePolicyDocument.Statement[0].Principal.Service' --output text` returns `eks.amazonaws.com`
  - [ ] `aws iam list-attached-role-policies --role-name max-weather-eks-node` includes `AmazonEKSWorkerNodePolicy` AND `AmazonEKS_CNI_Policy` AND `AmazonEC2ContainerRegistryReadOnly`
  - [ ] `aws iam get-instance-profile --instance-profile-name max-weather-jenkins` succeeds
  - [ ] AWS LB controller policy JSON file present at `infra/modules/iam/policies/aws-lb-controller.json` and matches `v2.8.2` upstream

  **QA Scenarios**:

  ```
  Scenario: All non-IRSA roles created with correct trust + policies
    Tool: interactive_bash
    Preconditions: T3, T4 done
    Steps:
      1. tmux: `cd infra/envs/staging && terraform apply -target=module.iam -auto-approve 2>&1 | tee /tmp/tf-iam.log`
      2. tmux: `for role in max-weather-eks-cluster max-weather-eks-node max-weather-jenkins; do aws iam get-role --role-name $role --query 'Role.[RoleName,Arn]' --output text; done | tee /tmp/roles.txt`
      3. Assert: 3 roles printed
      4. tmux: `aws iam list-attached-role-policies --role-name max-weather-eks-cluster --query 'AttachedPolicies[].PolicyName' --output json` → assert includes "AmazonEKSClusterPolicy"
      5. tmux: `aws iam get-instance-profile --instance-profile-name max-weather-jenkins --query 'InstanceProfile.Roles[0].RoleName' --output text` → assert "max-weather-jenkins"
    Expected Result: All 3 base roles + Jenkins instance profile present with correct policies
    Failure Indicators: any role missing or wrong attached policy
    Evidence: .sisyphus/evidence/task-05-roles.txt + docs/evidence/01-terraform/iam-state.json

  Scenario: IRSA roles created after EKS OIDC available (re-apply phase)
    Tool: interactive_bash
    Preconditions: T10 done (OIDC provider exists)
    Steps:
      1. tmux: `cd infra/envs/staging && terraform apply -target=module.iam -auto-approve` (now with OIDC ARN populated)
      2. tmux: `aws iam get-role --role-name max-weather-cluster-autoscaler --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals' --output json` → assert key matches `oidc.eks.<region>.amazonaws.com/id/<id>:sub`
      3. tmux: `aws iam get-role --role-name max-weather-fluent-bit` → succeeds
      4. tmux: `aws iam get-role --role-name max-weather-aws-lb-controller` → succeeds
    Expected Result: IRSA trust policies reference correct OIDC provider with correct sub claim
    Evidence: .sisyphus/evidence/task-05-irsa-trust.json
  ```

  **Evidence to Capture**:
  - [ ] task-05-roles.txt — base roles list
  - [ ] task-05-irsa-trust.json — IRSA trust policy verification
  - [ ] docs/evidence/01-terraform/iam-state.json — module state
  - [ ] infra/modules/iam/policies/aws-lb-controller.json (committed)

  **Commit**: YES (single commit)
  - Message: `feat(infra/modules/iam): roles, irsa, jenkins instance profile`
  - Files: `infra/modules/iam/*`
  - Pre-commit: `terraform_fmt`, `terraform_validate`, `gitleaks`

- [x] 6. **ECR module: 2 repositories with lifecycle + scanOnPush**

  **What to do**:
  - Create `infra/modules/ecr/{main.tf,variables.tf,outputs.tf,versions.tf,README.md}`
  - Resources:
    - `aws_ecr_repository.weather_api` (name: `max-weather/weather-api`) — `image_tag_mutability = "MUTABLE"` (for `latest` tag), `image_scanning_configuration.scan_on_push = true`, encryption AES256
    - `aws_ecr_repository.lambda_authorizer` (name: `max-weather/lambda-authorizer`) — same settings
    - `aws_ecr_lifecycle_policy` for both — keep last 10 tagged images; expire untagged after 7 days
    - `aws_ecr_repository_policy` allowing pull from EKS node role + Lambda execution role + Jenkins role
  - Variables: `name_prefix`, `eks_node_role_arn`, `lambda_authorizer_role_arn`, `jenkins_role_arn`, `tags`
  - Outputs: `weather_api_repository_url`, `weather_api_repository_arn`, `lambda_authorizer_repository_url`, `lambda_authorizer_repository_arn`

  **Must NOT do**:
  - Do NOT enable `image_tag_mutability = IMMUTABLE` (we use `latest` for staging; semver for prod)
  - Do NOT skip scan-on-push (PDF mandates security)
  - Do NOT allow pull from `*` principals — restrict to specific role ARNs

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Small focused module with 2 repos.
  - **Skills**: [`terraform-style-guide`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 3)
  - **Parallel Group**: Wave 3 — with T4, T5, T7, T8, T9
  - **Blocks**: T22 (Lambda authorizer needs repo), T24 (build+push needs URL)
  - **Blocked By**: T3, T5 (needs IAM role ARNs for repository policy)

  **References**:
  - **Pattern References**: `terraform-style-guide` skill
  - **External References**:
    - ECR lifecycle policy JSON syntax: `https://docs.aws.amazon.com/AmazonECR/latest/userguide/lifecycle_policy_examples.html`
  - **WHY Each Reference Matters**:
    - Lifecycle policy syntax errors silently no-op — must validate via API after apply

  **Acceptance Criteria**:
  - [ ] `terraform validate` + `fmt -check` pass
  - [ ] `aws ecr describe-repositories --repository-names max-weather/weather-api max-weather/lambda-authorizer --query 'repositories[].imageScanningConfiguration.scanOnPush' --output json` returns `[true, true]`
  - [ ] `aws ecr get-lifecycle-policy --repository-name max-weather/weather-api` returns policy with rules

  **QA Scenarios**:

  ```
  Scenario: ECR repositories with scan-on-push and lifecycle
    Tool: Bash
    Preconditions: T3, T5 done
    Steps:
      1. `cd infra/envs/staging && terraform apply -target=module.ecr -auto-approve`
      2. `aws ecr describe-repositories --repository-names max-weather/weather-api --query 'repositories[0].imageScanningConfiguration.scanOnPush' --output text` → assert "True"
      3. `aws ecr get-lifecycle-policy --repository-name max-weather/weather-api --query 'lifecyclePolicyText' --output text | jq '.rules | length'` → assert >= 2
      4. Save: `aws ecr describe-repositories --repository-names max-weather/weather-api max-weather/lambda-authorizer > docs/evidence/01-terraform/ecr-repos.json`
    Expected Result: Both repos present with scan-on-push and lifecycle policy
    Evidence: docs/evidence/01-terraform/ecr-repos.json + .sisyphus/evidence/task-06-validation.txt
  ```

  **Evidence to Capture**:
  - [ ] task-06-validation.txt — repo verification outputs
  - [ ] docs/evidence/01-terraform/ecr-repos.json — repo descriptions

  **Commit**: YES (single commit)
  - Message: `feat(infra/modules/ecr): two repos with scan-on-push and lifecycle`
  - Files: `infra/modules/ecr/*`
  - Pre-commit: `terraform_fmt`, `terraform_validate`, `gitleaks`

- [x] 7. **Secrets Manager module: Cognito client_secret + app config secrets**

  **What to do**:
  - Create `infra/modules/secrets/{main.tf,variables.tf,outputs.tf,versions.tf,README.md}`
  - Resources:
    - `aws_secretsmanager_secret.cognito_client_secret` (name: `max-weather/cognito/client-secret`) — value populated POST-Cognito creation via `aws_secretsmanager_secret_version` referencing T9 output
    - `aws_secretsmanager_secret.app_config_staging` (name: `max-weather/staging/app-config`) — JSON: `{ "WEATHER_API_BASE": "https://api.open-meteo.com/v1", "LOG_LEVEL": "info" }`
    - `aws_secretsmanager_secret.app_config_prod` (name: `max-weather/prod/app-config`) — same shape, prod values
    - `aws_secretsmanager_secret_policy` allowing `external_secrets` IRSA role + `lambda_authorizer` role to `GetSecretValue`
    - `recovery_window_in_days = 0` for all (so `terraform destroy` works without 7-day wait)
  - Variables: `name_prefix`, `external_secrets_role_arn`, `lambda_authorizer_role_arn`, `cognito_client_secret` (sensitive, optional — wired from T9), `tags`
  - Outputs: `cognito_secret_arn`, `app_config_staging_arn`, `app_config_prod_arn`

  **Must NOT do**:
  - Do NOT hardcode secret VALUES in .tf files — accept as variables or set via CLI
  - Do NOT use `recovery_window_in_days > 0` in this assessment (blocks teardown)
  - Do NOT commit any actual secret value to git

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Small module with 3 secrets + policies.
  - **Skills**: [`terraform-style-guide`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 3)
  - **Parallel Group**: Wave 3 — with T4, T5, T6, T8, T9
  - **Blocks**: T17 (External Secrets Operator needs ARNs), T22 (Lambda authorizer reads Cognito secret)
  - **Blocked By**: T3, T5 (needs role ARNs)

  **References**:
  - **Pattern References**: `terraform-style-guide` skill
  - **External References**:
    - Secrets Manager resource policy: `https://docs.aws.amazon.com/secretsmanager/latest/userguide/auth-and-access_resource-policies.html`
  - **WHY Each Reference Matters**:
    - Resource-based policy + IRSA combination is required for cross-namespace access in EKS

  **Acceptance Criteria**:
  - [ ] `terraform validate` + `fmt -check` pass
  - [ ] After apply: `aws secretsmanager describe-secret --secret-id max-weather/staging/app-config` returns secret with policy attached
  - [ ] `aws secretsmanager get-resource-policy --secret-id max-weather/staging/app-config` shows policy allowing IRSA role

  **QA Scenarios**:

  ```
  Scenario: Secrets created with correct resource policy
    Tool: Bash
    Preconditions: T3, T5 done
    Steps:
      1. `cd infra/envs/staging && terraform apply -target=module.secrets -auto-approve`
      2. `aws secretsmanager list-secrets --query 'SecretList[?starts_with(Name, `max-weather/`)].Name' --output json | tee /tmp/secrets.json`
      3. Assert via jq: includes "max-weather/cognito/client-secret", "max-weather/staging/app-config", "max-weather/prod/app-config"
      4. `aws secretsmanager get-resource-policy --secret-id max-weather/staging/app-config --query 'ResourcePolicy' --output text | jq '.Statement[0].Principal.AWS'` → contains external_secrets role ARN
    Expected Result: 3 secrets present; policies grant correct role access
    Evidence: docs/evidence/01-terraform/secrets-list.json + .sisyphus/evidence/task-07-policies.json
  ```

  **Evidence to Capture**:
  - [ ] task-07-policies.json — resource policy verification
  - [ ] docs/evidence/01-terraform/secrets-list.json — secret list

  **Commit**: YES (single commit)
  - Message: `feat(infra/modules/secrets): cognito + app config secrets with resource policies`
  - Files: `infra/modules/secrets/*`
  - Pre-commit: `terraform_fmt`, `terraform_validate`, `gitleaks`

- [x] 8. **CloudWatch Logs module: log groups + retention**

  **What to do**:
  - Create `infra/modules/logging/{main.tf,variables.tf,outputs.tf,versions.tf,README.md}`
  - Resources:
    - `aws_cloudwatch_log_group.eks_cluster` (name: `/aws/eks/max-weather/cluster`) — retention 7 days
    - `aws_cloudwatch_log_group.application` (name: `/aws/eks/max-weather/application`) — retention 7 days (Fluent Bit target)
    - `aws_cloudwatch_log_group.dataplane` (name: `/aws/eks/max-weather/dataplane`) — retention 7 days (Fluent Bit kubelet/containerd target)
    - `aws_cloudwatch_log_group.host` (name: `/aws/eks/max-weather/host`) — retention 7 days (Fluent Bit host messages)
    - `aws_cloudwatch_log_group.lambda_authorizer` (name: `/aws/lambda/max-weather-authorizer`) — retention 7 days
    - `aws_cloudwatch_log_group.api_gateway` (name: `/aws/apigateway/max-weather`) — retention 7 days
  - Variables: `name_prefix`, `retention_days` (default 7), `tags`
  - Outputs: all log group names + ARNs (used by EKS cluster logging config + Fluent Bit configmap + Lambda + API GW)

  **Must NOT do**:
  - Do NOT set retention to "Never expire" (cost trap)
  - Do NOT skip the eks-cluster log group — EKS control plane logs need it pre-created

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Trivial module with 6 log groups.
  - **Skills**: [`terraform-style-guide`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 3)
  - **Parallel Group**: Wave 3 — with T4, T5, T6, T7, T9
  - **Blocks**: T10 (EKS cluster references log group), T15 (Fluent Bit configmap references log groups), T22 (Lambda runtime), T27 (API GW logging)
  - **Blocked By**: T3

  **References**:
  - **Pattern References**: `terraform-style-guide` skill
  - **External References**:
    - EKS control plane logging: `https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html`
  - **WHY Each Reference Matters**:
    - EKS expects `/aws/eks/<cluster>/cluster` log group pre-created with correct retention

  **Acceptance Criteria**:
  - [ ] `terraform validate` + `fmt -check` pass
  - [ ] All 6 log groups exist with `retentionInDays = 7`: `aws logs describe-log-groups --log-group-name-prefix /aws/eks/max-weather --query 'logGroups[].[logGroupName,retentionInDays]' --output text`

  **QA Scenarios**:

  ```
  Scenario: Log groups created with retention
    Tool: Bash
    Preconditions: T3 done
    Steps:
      1. `cd infra/envs/staging && terraform apply -target=module.logging -auto-approve`
      2. `aws logs describe-log-groups --query 'logGroups[?starts_with(logGroupName, `/aws/eks/max-weather`) || starts_with(logGroupName, `/aws/lambda/max-weather`) || starts_with(logGroupName, `/aws/apigateway/max-weather`)].[logGroupName,retentionInDays]' --output json | tee docs/evidence/01-terraform/log-groups.json`
      3. Assert via jq: count == 6 AND all retentionInDays == 7
    Expected Result: 6 log groups present with 7-day retention
    Evidence: docs/evidence/01-terraform/log-groups.json + .sisyphus/evidence/task-08-validation.txt
  ```

  **Evidence to Capture**:
  - [ ] task-08-validation.txt — log group validation
  - [ ] docs/evidence/01-terraform/log-groups.json — log group list

  **Commit**: YES (single commit)
  - Message: `feat(infra/modules/logging): cloudwatch log groups with 7-day retention`
  - Files: `infra/modules/logging/*`
  - Pre-commit: `terraform_fmt`, `terraform_validate`, `gitleaks`

- [x] 9. **Cognito module: User Pool + Resource Server + Client (client_credentials)**

  **What to do**:
  - Create `infra/modules/cognito/{main.tf,variables.tf,outputs.tf,versions.tf,README.md}`
  - Resources:
    - `aws_cognito_user_pool.max_weather` — name `max-weather-pool`, MFA OFF (machine-to-machine), no auto-verify
    - `aws_cognito_user_pool_domain.max_weather` — domain prefix `max-weather-${random_id.suffix.hex}` (must be globally unique within region)
    - `aws_cognito_resource_server.weather` — identifier `weather-api`, name `Weather API`, scopes: `[{ scope_name = "read", scope_description = "Read weather data" }]`
    - `aws_cognito_user_pool_client.weather_client` — name `max-weather-client`, `generate_secret = true`, `allowed_oauth_flows = ["client_credentials"]`, `allowed_oauth_flows_user_pool_client = true`, `allowed_oauth_scopes = ["weather-api/read"]`, no callback/logout URLs (M2M)
    - `random_id.suffix` (4 bytes hex) for domain uniqueness
  - Variables: `name_prefix`, `region`, `tags`
  - Outputs: `user_pool_id`, `user_pool_arn`, `user_pool_domain`, `client_id`, `client_secret` (sensitive), `token_endpoint` (constructed: `https://${domain}.auth.${region}.amazoncognito.com/oauth2/token`), `jwks_uri` (`https://cognito-idp.${region}.amazonaws.com/${user_pool_id}/.well-known/jwks.json`), `issuer` (`https://cognito-idp.${region}.amazonaws.com/${user_pool_id}`)
  - In root staging env: pipe `client_secret` output → `module.secrets.cognito_client_secret` variable (creates implicit dependency)

  **Must NOT do**:
  - Do NOT enable user sign-up (M2M only)
  - Do NOT use Implicit grant or Authorization Code (only client_credentials)
  - Do NOT echo `client_secret` to logs — mark output sensitive
  - Do NOT skip the resource server scope — Cognito rejects token requests without `scope` param

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Cognito has subtle config (resource server vs scope vs client allowed_oauth_scopes mismatch is the #1 rookie error).
  - **Skills**: [`terraform-style-guide`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 3)
  - **Parallel Group**: Wave 3 — with T4, T5, T6, T7, T8
  - **Blocks**: T22 (Lambda authorizer needs JWKS URI + issuer), T27 (Postman needs token endpoint + client creds), T7 (secret value population, but secret container exists already)
  - **Blocked By**: T3

  **References**:
  - **Pattern References**: `terraform-style-guide` skill; analysis doc §5 (Auth flow)
  - **External References**:
    - Cognito M2M client_credentials: `https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-app-idp-settings.html#cognito-user-pools-app-idp-settings-client-credentials`
    - Cognito JWKS endpoint format: `https://docs.aws.amazon.com/cognito/latest/developerguide/amazon-cognito-user-pools-using-tokens-verifying-a-jwt.html`
  - **WHY Each Reference Matters**:
    - Resource server `identifier` + scope name combine to form `<identifier>/<scope>` — must use this exact string in client `allowed_oauth_scopes` and Lambda authorizer scope check
    - JWKS URI format is region-and-pool-specific; wrong URL = authorizer fails to verify tokens

  **Acceptance Criteria**:
  - [ ] `terraform validate` + `fmt -check` pass
  - [ ] After apply: token endpoint returns 200 with valid token:
    ```
    curl -sf -X POST -u "$CLIENT_ID:$CLIENT_SECRET" -d "grant_type=client_credentials&scope=weather-api/read" "$TOKEN_ENDPOINT" | jq -e '.access_token'
    ```
  - [ ] JWKS URI returns valid JSON: `curl -sf "$JWKS_URI" | jq -e '.keys[0].kid'`
  - [ ] Token decodes with correct issuer + scope (jwt-cli or `jq` on base64-decoded payload)

  **QA Scenarios**:

  ```
  Scenario: Cognito issues client_credentials token
    Tool: interactive_bash
    Preconditions: T3 done
    Steps:
      1. tmux: `cd infra/envs/staging && terraform apply -target=module.cognito -auto-approve 2>&1 | tee /tmp/tf-cognito.log`
      2. tmux: `CLIENT_ID=$(terraform output -raw cognito_client_id); CLIENT_SECRET=$(terraform output -raw cognito_client_secret); TOKEN_ENDPOINT=$(terraform output -raw cognito_token_endpoint)`
      3. tmux: `TOKEN=$(curl -sf -X POST -u "$CLIENT_ID:$CLIENT_SECRET" -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=client_credentials&scope=weather-api/read" "$TOKEN_ENDPOINT" | jq -r .access_token)`
      4. Assert: `[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]`
      5. tmux: decode JWT payload via `echo $TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq .` → assert `.scope == "weather-api/read"` AND `.token_use == "access"`
      6. Save: token sample (REDACTED to first 20 chars) + decoded payload to `.sisyphus/evidence/task-09-token-sample.json`
    Expected Result: Valid JWT with correct scope and token_use
    Failure Indicators: HTTP 400 (scope mismatch), 401 (client_secret wrong), empty access_token
    Evidence: .sisyphus/evidence/task-09-token-sample.json (no full secret in repo)

  Scenario: JWKS endpoint serves keys
    Tool: Bash
    Steps:
      1. `JWKS=$(terraform output -raw cognito_jwks_uri)`
      2. `curl -sf "$JWKS" | jq -e '.keys | length > 0'`
    Expected Result: JWKS endpoint returns >= 1 key
    Evidence: .sisyphus/evidence/task-09-jwks.json (public keys, safe to commit)

  Scenario: client_secret wired into Secrets Manager
    Tool: Bash
    Preconditions: T7 module re-applied with cognito secret value
    Steps:
      1. `cd infra/envs/staging && terraform apply -target=module.secrets -auto-approve`
      2. `aws secretsmanager get-secret-value --secret-id max-weather/cognito/client-secret --query SecretString --output text | wc -c` → assert > 20
    Expected Result: Secret value populated; not empty
    Evidence: .sisyphus/evidence/task-09-secret-populated.txt (length only, not value)
  ```

  **Evidence to Capture**:
  - [ ] task-09-token-sample.json — redacted token + decoded payload
  - [ ] task-09-jwks.json — public JWKS response
  - [ ] task-09-secret-populated.txt — secret length proof (no value)
  - [ ] docs/evidence/01-terraform/cognito-state.json — module state (sensitive fields stripped)

  **Commit**: YES (single commit)
  - Message: `feat(infra/modules/cognito): user pool + resource server + m2m client_credentials`
  - Files: `infra/modules/cognito/*`
  - Pre-commit: `terraform_fmt`, `terraform_validate`, `gitleaks`

- [x] 10. **EKS cluster module: control plane + OIDC provider + control-plane logging**

  **What to do**:
  - Create `infra/modules/eks-cluster/{main.tf,variables.tf,outputs.tf,versions.tf,README.md}`
  - Resources:
    - `aws_eks_cluster.main` — name `max-weather`, version `1.30`, role from IAM module, vpc_config: subnet_ids = public + private subnets, `endpoint_public_access = true`, `endpoint_private_access = true`, `public_access_cidrs = var.allowed_cidrs` (user IP /32, NOT 0.0.0.0/0), enabled_cluster_log_types: `["api", "audit", "authenticator", "controllerManager", "scheduler"]`
    - `aws_iam_openid_connect_provider.eks` — URL from cluster OIDC issuer; client_list `["sts.amazonaws.com"]`; thumbprint via `data "tls_certificate"` (do NOT hardcode)
    - `aws_eks_addon.vpc_cni` — version pinned (lookup latest compatible with 1.30 via `data "aws_eks_addon_version"`)
    - `aws_eks_addon.coredns` — version pinned
    - `aws_eks_addon.kube_proxy` — version pinned
    - `aws_eks_addon.eks_pod_identity_agent` — for future pod-identity migration (optional, low cost)
  - Variables: `cluster_name`, `cluster_version` (default `1.30`), `cluster_role_arn`, `subnet_ids`, `allowed_cidrs` (list of strings, REQUIRED — no default), `tags`
  - Outputs: `cluster_name`, `cluster_endpoint`, `cluster_certificate_authority_data`, `cluster_oidc_issuer_url`, `oidc_provider_arn`, `oidc_provider_url` (without `https://` — used in IRSA trust policies)

  **Must NOT do**:
  - Do NOT use `endpoint_public_access_cidrs = ["0.0.0.0/0"]` (security regression)
  - Do NOT skip OIDC provider (IRSA depends on it)
  - Do NOT hardcode thumbprint (rotates; use tls_certificate data source)
  - Do NOT skip control-plane log types (PDF mandates CloudWatch testing)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: EKS cluster is the highest-stakes resource (long apply, hard to fix mistakes); OIDC subtleties.
  - **Skills**: [`terraform-style-guide`]

  **Parallelization**:
  - **Can Run In Parallel**: NO (dependencies serialize this)
  - **Parallel Group**: Wave 4 (alone — long-running, ~12-15 min apply)
  - **Blocks**: T11, T12, T13–T19, T23 (everything K8s needs cluster up)
  - **Blocked By**: T4 (subnets), T5 (cluster role), T8 (log group)

  **References**:
  - **Pattern References**: `terraform-style-guide` skill; analysis doc §4.4
  - **External References**:
    - EKS endpoint access modes: `https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html`
    - OIDC provider thumbprint via tls_certificate: `https://registry.terraform.io/providers/hashicorp/tls/latest/docs/data-sources/certificate`
    - EKS addon versions API: `aws eks describe-addon-versions --kubernetes-version 1.30 --addon-name vpc-cni`
  - **WHY Each Reference Matters**:
    - `endpoint_public_access` + `public_access_cidrs` is the only sane way for solo developer to use kubectl from laptop without bastion
    - tls_certificate-derived thumbprint auto-rotates; hardcoded thumbprint becomes stale and breaks IRSA silently
    - Pinned addon versions = reproducible builds

  **Acceptance Criteria**:
  - [ ] `terraform validate` + `fmt -check` pass
  - [ ] After apply: `aws eks describe-cluster --name max-weather --query 'cluster.[status,version]' --output text` returns `ACTIVE\t1.30`
  - [ ] `aws eks describe-cluster --name max-weather --query 'cluster.resourcesVpcConfig.publicAccessCidrs' --output json` returns NOT `["0.0.0.0/0"]`
  - [ ] `aws eks describe-cluster --name max-weather --query 'cluster.logging.clusterLogging[0].types' --output json` includes all 5 types
  - [ ] OIDC provider exists: `aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[?contains(Arn, `oidc.eks`)] | length(@)'` returns >= 1
  - [ ] `aws eks update-kubeconfig --name max-weather --region us-east-1 && kubectl get nodes` succeeds (0 nodes OK at this stage)

  **QA Scenarios**:

  ```
  Scenario: EKS cluster ACTIVE with restricted public endpoint
    Tool: interactive_bash
    Preconditions: T4, T5, T8 done; user IP CIDR known
    Steps:
      1. tmux: `MY_IP=$(curl -s https://checkip.amazonaws.com)/32`
      2. tmux: `cd infra/envs/staging && terraform apply -target=module.eks_cluster -var "allowed_cidrs=[\"$MY_IP\"]" -auto-approve 2>&1 | tee /tmp/tf-eks.log` (this takes 12-15 min)
      3. tmux: `aws eks describe-cluster --name max-weather --query 'cluster.status' --output text` → assert "ACTIVE"
      4. tmux: `aws eks describe-cluster --name max-weather --query 'cluster.resourcesVpcConfig.publicAccessCidrs' --output json | jq -e ". != [\"0.0.0.0/0\"]"`
      5. tmux: `aws eks update-kubeconfig --name max-weather --region us-east-1`
      6. tmux: `kubectl get nodes` → assert exit 0 (0 nodes expected at this stage)
      7. tmux: `kubectl get --raw /healthz` → assert "ok"
    Expected Result: Cluster ACTIVE; kubectl works; endpoint restricted
    Failure Indicators: cluster status not ACTIVE, public_access_cidrs == 0.0.0.0/0, kubectl unauthorized
    Evidence: docs/evidence/02-eks/cluster-describe.json + .sisyphus/evidence/task-10-validation.txt

  Scenario: OIDC provider created with cert-derived thumbprint
    Tool: Bash
    Steps:
      1. `OIDC_URL=$(aws eks describe-cluster --name max-weather --query 'cluster.identity.oidc.issuer' --output text)`
      2. `aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, '${OIDC_URL##https://}')]"`
      3. Assert: returns 1 entry
    Expected Result: OIDC provider linked to cluster issuer
    Evidence: .sisyphus/evidence/task-10-oidc.json

  Scenario: Control plane logs flowing to CloudWatch
    Tool: Bash
    Steps:
      1. Wait 60s after cluster ACTIVE
      2. `aws logs filter-log-events --log-group-name /aws/eks/max-weather/cluster --start-time $(date -d '5 min ago' +%s)000 --max-items 5 --query 'events[].message' --output text`
      3. Assert: returns >= 1 line
    Expected Result: EKS control plane writing to log group
    Evidence: .sisyphus/evidence/task-10-cp-logs.txt
  ```

  **Evidence to Capture**:
  - [ ] task-10-validation.txt — cluster + endpoint validation
  - [ ] task-10-oidc.json — OIDC provider proof
  - [ ] task-10-cp-logs.txt — control plane log sample
  - [ ] docs/evidence/02-eks/cluster-describe.json — full cluster description

  **Commit**: YES (single commit)
  - Message: `feat(infra/modules/eks-cluster): control plane v1.30 with restricted endpoint, oidc, control-plane logging`
  - Files: `infra/modules/eks-cluster/*`, `infra/envs/staging/eks.tf` (module call)
  - Pre-commit: `terraform_fmt`, `terraform_validate`, `gitleaks`

- [x] 11. **EKS managed node group module: t3.medium 2-10 nodes across 3 AZs**

  **What to do**:
  - Create `infra/modules/eks-nodegroup/{main.tf,variables.tf,outputs.tf,versions.tf,README.md}`
  - Resources:
    - `aws_eks_node_group.main` — cluster_name from variable, node_role_arn from IAM module, subnet_ids = private subnets only, instance_types `["t3.medium"]`, capacity_type `ON_DEMAND` (mix `SPOT` blocked — assessment scope), AMI type `AL2023_x86_64_STANDARD`, disk_size 20 GB, scaling_config: min 2, max 10, desired 2; update_config: max_unavailable 1; labels: `{ role = "general" }`; tags include `k8s.io/cluster-autoscaler/enabled = "true"` and `k8s.io/cluster-autoscaler/max-weather = "owned"` (for autoscaler discovery)
    - `aws_launch_template.main` (optional but recommended) — for node user data customization (e.g., bootstrap.sh args); references via `launch_template { id, version }` block
  - Variables: `cluster_name`, `node_role_arn`, `private_subnet_ids`, `instance_types` (default `["t3.medium"]`), `min_size` (default 2), `max_size` (default 10), `desired_size` (default 2), `disk_size` (default 20), `tags`
  - Outputs: `node_group_name`, `node_group_arn`, `asg_names`

  **Must NOT do**:
  - Do NOT place nodes in public subnets
  - Do NOT use `MIXED` capacity_type with spot (assessment scope says ON_DEMAND only)
  - Do NOT skip cluster-autoscaler tags — autoscaler discovers ASGs via these tags
  - Do NOT use AL2 (deprecated for new clusters; use AL2023)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Node group config has scaling + tagging subtleties; mistakes break HPA/CA.
  - **Skills**: [`terraform-style-guide`]

  **Parallelization**:
  - **Can Run In Parallel**: NO (depends on T10)
  - **Parallel Group**: Wave 4 — sequential after T10
  - **Blocks**: T13–T19 (need nodes Ready)
  - **Blocked By**: T4 (private subnets), T5 (node role), T10 (cluster ACTIVE)

  **References**:
  - **Pattern References**: `terraform-style-guide` skill
  - **External References**:
    - Cluster Autoscaler ASG tag requirements: `https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md#auto-discovery-setup`
    - AL2023 EKS AMI: `https://docs.aws.amazon.com/eks/latest/userguide/al2023.html`
  - **WHY Each Reference Matters**:
    - Autoscaler refuses to scale ASGs without the exact `k8s.io/cluster-autoscaler/<cluster>` tag — silent failure
    - AL2 deprecation: future EKS versions drop AL2; AL2023 is the forward-compatible choice

  **Acceptance Criteria**:
  - [ ] `terraform validate` + `fmt -check` pass
  - [ ] After apply: `aws eks describe-nodegroup --cluster-name max-weather --nodegroup-name <name> --query 'nodegroup.status' --output text` returns `ACTIVE`
  - [ ] `kubectl get nodes` returns 2 nodes in `Ready` state, distributed across 3 AZs (verify with `kubectl get nodes -L topology.kubernetes.io/zone`)
  - [ ] ASG has `k8s.io/cluster-autoscaler/max-weather=owned` tag

  **QA Scenarios**:

  ```
  Scenario: Node group ACTIVE with 2 nodes Ready
    Tool: interactive_bash
    Preconditions: T10 done
    Steps:
      1. tmux: `cd infra/envs/staging && terraform apply -target=module.eks_nodegroup -auto-approve 2>&1 | tee /tmp/tf-ng.log` (~5-7 min)
      2. tmux: `aws eks describe-nodegroup --cluster-name max-weather --nodegroup-name $(terraform output -raw nodegroup_name) --query 'nodegroup.status' --output text` → assert "ACTIVE"
      3. tmux: `kubectl wait --for=condition=Ready nodes --all --timeout=300s`
      4. tmux: `kubectl get nodes -L topology.kubernetes.io/zone -o wide | tee /tmp/nodes.txt`
      5. Assert: 2 nodes Ready
      6. tmux: `ASG=$(terraform output -json | jq -r '.nodegroup_asg_names.value[0]'); aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG --query 'AutoScalingGroups[0].Tags[?Key==`k8s.io/cluster-autoscaler/max-weather`].Value' --output text` → assert "owned"
    Expected Result: 2 nodes Ready; ASG tagged for autoscaler discovery
    Failure Indicators: nodes NotReady, ASG missing autoscaler tag
    Evidence: docs/evidence/02-eks/nodes.txt + .sisyphus/evidence/task-11-validation.txt
  ```

  **Evidence to Capture**:
  - [ ] task-11-validation.txt — node + ASG validation
  - [ ] docs/evidence/02-eks/nodes.txt — `kubectl get nodes -o wide`

  **Commit**: YES (single commit)
  - Message: `feat(infra/modules/eks-nodegroup): on-demand t3.medium 2-10 nodes with autoscaler tags`
  - Files: `infra/modules/eks-nodegroup/*`
  - Pre-commit: `terraform_fmt`, `terraform_validate`, `gitleaks`

- [x] 12. **EKS access entries: kubectl access for Jenkins + operator**

  **What to do**:
  - Add to `infra/modules/eks-cluster/access.tf` (or sub-module):
    - `aws_eks_access_entry.operator` — principal = current AWS caller ARN (input variable `operator_principal_arn`); type `STANDARD`
    - `aws_eks_access_policy_association.operator_admin` — associate `AmazonEKSClusterAdminPolicy` with cluster scope
    - `aws_eks_access_entry.jenkins` — principal = Jenkins role ARN; type `STANDARD`
    - `aws_eks_access_policy_association.jenkins_edit` — associate `AmazonEKSEditPolicy` with namespace scope `["weather-staging", "weather-prod"]`
  - Variables: `operator_principal_arn` (REQUIRED), `jenkins_role_arn` (REQUIRED)
  - Use access entries (not legacy aws-auth ConfigMap)

  **Must NOT do**:
  - Do NOT use the deprecated `aws-auth` ConfigMap — use access entries (cluster created with `authenticationMode = API_AND_CONFIG_MAP` or `API`)
  - Do NOT give Jenkins cluster-admin (least privilege: namespace-scoped Edit)
  - Do NOT skip operator entry (you'll lose kubectl access on next role assumption)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Small focused addition.
  - **Skills**: [`terraform-style-guide`]

  **Parallelization**:
  - **Can Run In Parallel**: NO (extends T10's module)
  - **Parallel Group**: Wave 4 — after T10
  - **Blocks**: T13–T19 (Jenkins/operator need kubectl access)
  - **Blocked By**: T5 (Jenkins role ARN), T10 (cluster), T11 (recommended; nothing fails without it)

  **References**:
  - **Pattern References**: `terraform-style-guide` skill
  - **External References**:
    - EKS access entries: `https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html`
    - Built-in access policies: `https://docs.aws.amazon.com/eks/latest/userguide/access-policies.html`
  - **WHY Each Reference Matters**:
    - Access entries are the modern replacement for aws-auth; required for `authenticationMode = API`
    - Built-in policies (`AmazonEKSEditPolicy`, `AmazonEKSClusterAdminPolicy`) replace hand-rolled RBAC

  **Acceptance Criteria**:
  - [ ] `terraform validate` + `fmt -check` pass
  - [ ] `aws eks list-access-entries --cluster-name max-weather --query 'accessEntries' --output json` includes operator + Jenkins ARNs
  - [ ] `aws eks list-associated-access-policies --cluster-name max-weather --principal-arn <jenkins-arn>` returns `AmazonEKSEditPolicy` scoped to `weather-staging` + `weather-prod`
  - [ ] `kubectl auth can-i create deployment -n weather-staging --as <jenkins-arn>` returns `yes`

  **QA Scenarios**:

  ```
  Scenario: Operator + Jenkins have correct EKS access
    Tool: interactive_bash
    Preconditions: T10, T11 done
    Steps:
      1. tmux: `OPERATOR=$(aws sts get-caller-identity --query Arn --output text)`
      2. tmux: `cd infra/envs/staging && terraform apply -target=module.eks_cluster.aws_eks_access_entry.operator -target=module.eks_cluster.aws_eks_access_entry.jenkins -auto-approve`
      3. tmux: `aws eks list-access-entries --cluster-name max-weather --query 'accessEntries' --output json | tee /tmp/entries.json`
      4. Assert via jq: includes operator ARN AND Jenkins role ARN
      5. tmux: `aws eks list-associated-access-policies --cluster-name max-weather --principal-arn $OPERATOR --query 'associatedAccessPolicies[].policyArn' --output text` → assert contains "AmazonEKSClusterAdminPolicy"
      6. tmux: `kubectl get nodes` → exits 0 with operator creds
    Expected Result: 2 access entries; operator can kubectl; Jenkins ARN present
    Evidence: .sisyphus/evidence/task-12-access-entries.json + docs/evidence/02-eks/access-entries.json
  ```

  **Evidence to Capture**:
  - [ ] task-12-access-entries.json — full access entry list
  - [ ] docs/evidence/02-eks/access-entries.json — same, for repo evidence

  **Commit**: YES (single commit)
  - Message: `feat(infra/modules/eks-cluster): access entries for operator (admin) + jenkins (edit)`
  - Files: `infra/modules/eks-cluster/access.tf`, variable updates
  - Pre-commit: `terraform_fmt`, `terraform_validate`, `gitleaks`

- [x] 13. **NGINX Ingress Controller via Helm (NLB exposure)**

  **What to do**:
  - Create `infra/modules/nginx-ingress/{main.tf,variables.tf,outputs.tf,versions.tf,values.yaml,README.md}`
  - Resources:
    - `helm_release.nginx_ingress` — chart `ingress-nginx`, repository `https://kubernetes.github.io/ingress-nginx`, version `4.11.3` (pin), namespace `ingress-nginx`, create_namespace = true
    - `values.yaml` content:
      ```
      controller:
        replicaCount: 2
        ingressClassResource: { name: nginx, default: true }
        service:
          type: LoadBalancer
          annotations:
            service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
            service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
            service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
            service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
        config:
          use-forwarded-headers: "true"
          enable-real-ip: "true"
        metrics: { enabled: true }
        resources:
          requests: { cpu: 100m, memory: 128Mi }
          limits: { memory: 256Mi }
      ```
    - Pass values via `values = [file("${path.module}/values.yaml")]`
  - Variables: `cluster_name`, `chart_version` (default `4.11.3`)
  - Outputs: `nlb_hostname` (lookup via `data "kubernetes_service" "nginx_ingress" {}`)
  - Provider: `helm` and `kubernetes` configured in env root using EKS cluster outputs

  **Must NOT do**:
  - Do NOT use ALB (PDF mandates NGINX Ingress Controller; ALB would skip the requirement)
  - Do NOT use `target-type: instance` (NLB→IP is the modern path; instance mode requires nodeport hassles)
  - Do NOT skip pinning chart version (drift = future breakage)
  - Do NOT install in `default` namespace

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: NLB+NGINX combo has well-known annotation pitfalls.
  - **Skills**: [`terraform-style-guide`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 5)
  - **Parallel Group**: Wave 5 — with T14, T15, T16, T17, T18, T19
  - **Blocks**: T23 (Ingress resource needs IngressClass `nginx`), T26 (Jenkinsfile health check needs NLB), T28 (API GW VPC link needs NLB)
  - **Blocked By**: T11 (nodes Ready), T12 (kubectl access), T16 (AWS LB Controller — strictly recommended; NLB-via-in-tree-controller works without it but legacy path)

  **References**:
  - **Pattern References**: `terraform-style-guide` skill; analysis doc §4.4 (ingress design)
  - **External References**:
    - ingress-nginx chart values: `https://github.com/kubernetes/ingress-nginx/blob/main/charts/ingress-nginx/values.yaml`
    - NLB annotations for AWS LB Controller: `https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.8/guide/service/annotations/`
  - **WHY Each Reference Matters**:
    - `aws-load-balancer-type: nlb` annotation is the trigger for AWS LB Controller to provision NLB (vs ALB)
    - `nlb-target-type: ip` skips NodePort hop, lower latency, supports cross-zone

  **Acceptance Criteria**:
  - [ ] `terraform validate` + `fmt -check` pass
  - [ ] `helm list -n ingress-nginx` shows release `nginx-ingress` STATUS deployed
  - [ ] `kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'` returns NLB hostname (`*.elb.us-east-1.amazonaws.com`)
  - [ ] NLB reachable: `curl -sI http://$NLB_HOST/ -m 10` returns HTTP 404 (default NGINX response when no Ingress matches)
  - [ ] IngressClass `nginx` exists and is default: `kubectl get ingressclass nginx -o jsonpath='{.metadata.annotations.ingressclass\.kubernetes\.io/is-default-class}'` returns `true`

  **QA Scenarios**:

  ```
  Scenario: NGINX Ingress + NLB provisioned
    Tool: interactive_bash
    Preconditions: T11, T12, T16 done
    Steps:
      1. tmux: `cd infra/envs/staging && terraform apply -target=module.nginx_ingress -auto-approve 2>&1 | tee /tmp/tf-nginx.log`
      2. tmux: `kubectl wait --for=condition=Available deployment/nginx-ingress-ingress-nginx-controller -n ingress-nginx --timeout=300s`
      3. tmux: `for i in {1..30}; do NLB=$(kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'); [ -n "$NLB" ] && break; sleep 10; done; echo "NLB=$NLB"`
      4. Assert: `[ -n "$NLB" ]`
      5. tmux: `for i in {1..30}; do CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$NLB/ -m 10); [ "$CODE" = "404" ] && break; sleep 10; done; echo "CODE=$CODE"` → assert "404"
      6. tmux: `kubectl get ingressclass nginx -o jsonpath='{.metadata.annotations.ingressclass\.kubernetes\.io/is-default-class}'` → assert "true"
      7. Save: NLB hostname + svc describe to docs/evidence/03-k8s/nginx-ingress.txt
    Expected Result: NLB DNS resolves and serves NGINX 404; IngressClass is default
    Failure Indicators: NLB hostname empty after 5 min, CODE != 404 (controller not bound)
    Evidence: docs/evidence/03-k8s/nginx-ingress.txt + .sisyphus/evidence/task-13-validation.txt
  ```

  **Evidence to Capture**:
  - [ ] task-13-validation.txt — controller + NLB validation
  - [ ] docs/evidence/03-k8s/nginx-ingress.txt — NLB hostname + svc describe

  **Commit**: YES (single commit)
  - Message: `feat(infra/modules/nginx-ingress): helm chart with nlb (ip target, internet-facing)`
  - Files: `infra/modules/nginx-ingress/*`
  - Pre-commit: `terraform_fmt`, `terraform_validate`, `gitleaks`

- [x] 14. **Cluster Autoscaler via Helm (with IRSA)**

  **What to do**:
  - Create `infra/modules/cluster-autoscaler/{main.tf,variables.tf,outputs.tf,versions.tf,values.yaml,README.md}`
  - Resources:
    - `helm_release.cluster_autoscaler` — chart `cluster-autoscaler`, repository `https://kubernetes.github.io/autoscaler`, version `9.37.0` (pin; matches CA 1.30.x), namespace `kube-system`
    - `values.yaml` content:
      ```
      autoDiscovery:
        clusterName: max-weather
      awsRegion: us-east-1
      rbac:
        serviceAccount:
          name: cluster-autoscaler
          annotations:
            eks.amazonaws.com/role-arn: <IRSA role ARN from T5>
      extraArgs:
        scale-down-delay-after-add: 5m
        scale-down-unneeded-time: 5m
        balance-similar-node-groups: true
        skip-nodes-with-system-pods: false
      ```
  - Variables: `cluster_name`, `region`, `irsa_role_arn`, `chart_version` (default `9.37.0`)
  - Outputs: helm release status

  **Must NOT do**:
  - Do NOT use Karpenter (assessment scope = Cluster Autoscaler only)
  - Do NOT skip IRSA (giving worker node role autoscaling perms is too permissive)
  - Do NOT mismatch CA chart version with K8s minor version (1.30 cluster → CA 1.30.x → chart 9.37.x)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: IRSA wiring + chart version pinning are common pitfalls.
  - **Skills**: [`terraform-style-guide`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 5)
  - **Parallel Group**: Wave 5 — with T13, T15, T16, T17, T18, T19
  - **Blocks**: T29 (load test → HPA → CA scale events)
  - **Blocked By**: T5 (IRSA role re-applied with OIDC), T11 (ASG with autoscaler tags)

  **References**:
  - **Pattern References**: `terraform-style-guide` skill
  - **External References**:
    - CA Helm chart: `https://github.com/kubernetes/autoscaler/blob/master/charts/cluster-autoscaler/values.yaml`
    - Version compatibility: `https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/README.md`
  - **WHY Each Reference Matters**:
    - Wrong CA version vs K8s = subtle API incompat → CA fails to scale silently

  **Acceptance Criteria**:
  - [ ] `terraform validate` + `fmt -check` pass
  - [ ] `helm list -n kube-system` shows release `cluster-autoscaler` STATUS deployed
  - [ ] `kubectl get sa cluster-autoscaler -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'` returns IRSA role ARN
  - [ ] `kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler --tail=50` shows lines like `Auto-discovered ASGs:` (not `denied`/`forbidden`)

  **QA Scenarios**:

  ```
  Scenario: Cluster Autoscaler installed with working IRSA
    Tool: interactive_bash
    Preconditions: T5 IRSA re-applied; T11 done
    Steps:
      1. tmux: `cd infra/envs/staging && terraform apply -target=module.cluster_autoscaler -auto-approve`
      2. tmux: `kubectl wait --for=condition=Available deployment/cluster-autoscaler-aws-cluster-autoscaler -n kube-system --timeout=180s`
      3. tmux: `kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler --tail=100 | tee /tmp/ca-logs.txt`
      4. Assert: grep -q "Auto-discovered" /tmp/ca-logs.txt
      5. Assert: ! grep -qi "denied\|forbidden\|AccessDenied" /tmp/ca-logs.txt
    Expected Result: CA running, discovering ASGs, no IAM access errors
    Failure Indicators: AccessDenied in logs (IRSA wrong), no ASG discovered (tags missing)
    Evidence: docs/evidence/03-k8s/cluster-autoscaler-logs.txt + .sisyphus/evidence/task-14-irsa.txt
  ```

  **Evidence to Capture**:
  - [ ] task-14-irsa.txt — IRSA verification (sa annotation + log scan)
  - [ ] docs/evidence/03-k8s/cluster-autoscaler-logs.txt — log sample

  **Commit**: YES (single commit)
  - Message: `feat(infra/modules/cluster-autoscaler): helm with irsa, auto-discovery`
  - Files: `infra/modules/cluster-autoscaler/*`
  - Pre-commit: `terraform_fmt`, `terraform_validate`, `gitleaks`

- [x] 15. **Fluent Bit DaemonSet via Helm (CloudWatch via IRSA)**

  **What to do**:
  - Create `infra/modules/fluent-bit/{main.tf,variables.tf,outputs.tf,versions.tf,values.yaml,README.md}`
  - Resources:
    - `helm_release.fluent_bit` — chart `aws-for-fluent-bit`, repository `https://aws.github.io/eks-charts`, version `0.1.34` (pin), namespace `amazon-cloudwatch`, create_namespace = true
    - `values.yaml`:
      ```
      cloudWatchLogs:
        enabled: true
        region: us-east-1
        logGroupName: /aws/eks/max-weather/application
        logStreamPrefix: fluent-bit-
        autoCreateGroup: false
      kinesis: { enabled: false }
      firehose: { enabled: false }
      elasticsearch: { enabled: false }
      serviceAccount:
        create: true
        name: fluent-bit
        annotations:
          eks.amazonaws.com/role-arn: <IRSA role ARN from T5>
      tolerations:
        - operator: Exists
      resources:
        requests: { cpu: 50m, memory: 100Mi }
        limits: { memory: 200Mi }
      ```
  - Variables: `region`, `log_group_name` (from T8 output), `irsa_role_arn`, `chart_version` (default `0.1.34`)
  - Outputs: helm release status

  **Must NOT do**:
  - Do NOT use `autoCreateGroup: true` (we manage log groups via Terraform; auto-create races + sets wrong retention)
  - Do NOT skip IRSA (node role too permissive)
  - Do NOT enable kinesis/firehose/elasticsearch (assessment scope = CloudWatch only)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Logging pipeline is on the critical path for PDF "CloudWatch testing" requirement.
  - **Skills**: [`terraform-style-guide`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 5)
  - **Parallel Group**: Wave 5 — with T13, T14, T16, T17, T18, T19
  - **Blocks**: T29 (load test → CloudWatch logs evidence)
  - **Blocked By**: T5 (IRSA), T8 (log group), T11 (nodes)

  **References**:
  - **Pattern References**: `terraform-style-guide` skill
  - **External References**:
    - aws-for-fluent-bit chart: `https://github.com/aws/eks-charts/tree/master/stable/aws-for-fluent-bit`
    - Fluent Bit IRSA setup: `https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-setup-logs-FluentBit.html`
  - **WHY Each Reference Matters**:
    - aws-for-fluent-bit chart bundles AWS plugins by default (vs upstream fluent-bit chart which needs config gymnastics)

  **Acceptance Criteria**:
  - [ ] `terraform validate` + `fmt -check` pass
  - [ ] `kubectl get ds -n amazon-cloudwatch` shows `aws-for-fluent-bit` with DESIRED == NUM_AVAILABLE
  - [ ] After ~2 min: `aws logs filter-log-events --log-group-name /aws/eks/max-weather/application --start-time $(date -d '5 min ago' +%s)000 --max-items 5` returns events
  - [ ] No `AccessDenied` in `kubectl logs -n amazon-cloudwatch ds/aws-for-fluent-bit --tail=100`

  **QA Scenarios**:

  ```
  Scenario: Fluent Bit ships logs to CloudWatch
    Tool: interactive_bash
    Preconditions: T5 IRSA re-applied; T8, T11 done
    Steps:
      1. tmux: `cd infra/envs/staging && terraform apply -target=module.fluent_bit -auto-approve`
      2. tmux: `kubectl rollout status ds/aws-for-fluent-bit -n amazon-cloudwatch --timeout=180s`
      3. tmux: deploy a busybox echo pod to generate logs: `kubectl run logger --image=busybox --restart=Never --rm -it -- sh -c 'for i in 1 2 3 4 5; do echo "test-log-$i"; sleep 1; done'`
      4. tmux: sleep 60 (Fluent Bit flush interval)
      5. tmux: `aws logs filter-log-events --log-group-name /aws/eks/max-weather/application --start-time $(date -d '5 min ago' +%s)000 --filter-pattern "test-log" --query 'events[].message' --output text | tee /tmp/cw-logs.txt`
      6. Assert: `grep -q "test-log" /tmp/cw-logs.txt`
    Expected Result: Logs from busybox pod appear in CloudWatch within 60s
    Failure Indicators: empty CW results, AccessDenied in fluent-bit logs
    Evidence: docs/evidence/04-cloudwatch/fluent-bit-evidence.txt + .sisyphus/evidence/task-15-cw-logs.txt
  ```

  **Evidence to Capture**:
  - [ ] task-15-cw-logs.txt — CW filter-log-events output
  - [ ] docs/evidence/04-cloudwatch/fluent-bit-evidence.txt — pipeline proof

  **Commit**: YES (single commit)
  - Message: `feat(infra/modules/fluent-bit): daemonset shipping logs to cloudwatch via irsa`
  - Files: `infra/modules/fluent-bit/*`
  - Pre-commit: `terraform_fmt`, `terraform_validate`, `gitleaks`

- [x] 16. **AWS Load Balancer Controller via Helm (with IRSA)**

  **What to do**:
  - Create `infra/modules/aws-lb-controller/{main.tf,variables.tf,outputs.tf,versions.tf,values.yaml,README.md}`
  - Resources:
    - `helm_release.aws_lb_controller` — chart `aws-load-balancer-controller`, repository `https://aws.github.io/eks-charts`, version `1.8.2` (pin), namespace `kube-system`
    - `values.yaml`:
      ```
      clusterName: max-weather
      region: us-east-1
      vpcId: <vpc-id from T4 output>
      serviceAccount:
        create: true
        name: aws-load-balancer-controller
        annotations:
          eks.amazonaws.com/role-arn: <IRSA from T5>
      replicaCount: 2
      ```
  - Variables: `cluster_name`, `region`, `vpc_id`, `irsa_role_arn`, `chart_version` (default `1.8.2`)
  - Outputs: helm release status

  **Must NOT do**:
  - Do NOT skip — without LB Controller, NLB-via-IP-target-type and modern annotations don't work
  - Do NOT mismatch IAM policy version (T5 uses `v2.8.2` JSON; chart `1.8.2` matches)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: [`terraform-style-guide`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 5)
  - **Parallel Group**: Wave 5 — with T13, T14, T15, T17, T18, T19
  - **Blocks**: T13 (NGINX NLB provisioning), T28 (API GW VPC link uses NLB)
  - **Blocked By**: T4 (vpc_id), T5 (IRSA re-applied), T11 (nodes)

  **References**:
  - **Pattern References**: `terraform-style-guide` skill
  - **External References**:
    - AWS LB Controller install: `https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.8/deploy/installation/`
  - **WHY Each Reference Matters**:
    - Chart values vs IAM policy version skew = silent feature loss; pin both to matched releases

  **Acceptance Criteria**:
  - [ ] `terraform validate` + `fmt -check` pass
  - [ ] `kubectl get deployment aws-load-balancer-controller -n kube-system` shows AVAILABLE == DESIRED
  - [ ] `kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=50 | grep -i "starting reconciler"` succeeds
  - [ ] No `AccessDenied` errors in last 100 log lines

  **QA Scenarios**:

  ```
  Scenario: AWS LB Controller running, no IAM errors
    Tool: interactive_bash
    Preconditions: T5 IRSA re-applied; T11 done
    Steps:
      1. tmux: `cd infra/envs/staging && terraform apply -target=module.aws_lb_controller -auto-approve`
      2. tmux: `kubectl wait --for=condition=Available deployment/aws-load-balancer-controller -n kube-system --timeout=180s`
      3. tmux: `kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=200 | tee /tmp/lbc-logs.txt`
      4. Assert: `grep -q "starting reconciler" /tmp/lbc-logs.txt || grep -q "successfully" /tmp/lbc-logs.txt`
      5. Assert: `! grep -qi "AccessDenied" /tmp/lbc-logs.txt`
    Expected Result: Controller running, reconciling, no IAM errors
    Failure Indicators: AccessDenied (IRSA broken), webhook errors (cert-manager missing — chart bundles its own)
    Evidence: docs/evidence/03-k8s/aws-lb-controller-logs.txt + .sisyphus/evidence/task-16-validation.txt
  ```

  **Evidence to Capture**:
  - [ ] task-16-validation.txt — controller validation
  - [ ] docs/evidence/03-k8s/aws-lb-controller-logs.txt — log sample

  **Commit**: YES (single commit)
  - Message: `feat(infra/modules/aws-lb-controller): helm install with irsa for nlb provisioning`
  - Files: `infra/modules/aws-lb-controller/*`
  - Pre-commit: `terraform_fmt`, `terraform_validate`, `gitleaks`

- [x] 17. **External Secrets Operator via Helm + ClusterSecretStore**

  **What to do**:
  - Create `infra/modules/external-secrets/{main.tf,variables.tf,outputs.tf,versions.tf,values.yaml,clustersecretstore.yaml,README.md}`
  - Resources:
    - `helm_release.external_secrets` — chart `external-secrets`, repository `https://charts.external-secrets.io`, version `0.10.4` (pin), namespace `external-secrets`, create_namespace = true
    - `kubernetes_manifest.cluster_secret_store_aws` — `ClusterSecretStore` named `aws-secretsmanager` referencing IRSA service account `external-secrets/external-secrets`
    - `values.yaml`:
      ```
      installCRDs: true
      serviceAccount:
        create: true
        name: external-secrets
        annotations:
          eks.amazonaws.com/role-arn: <IRSA from T5>
      replicaCount: 1
      ```
  - Variables: `region`, `irsa_role_arn`, `chart_version` (default `0.10.4`)
  - Outputs: helm release status, ClusterSecretStore name

  **Must NOT do**:
  - Do NOT use legacy SecretStore (namespaced) — ClusterSecretStore allows reuse across staging/prod namespaces
  - Do NOT skip CRD install (chart must install CRDs)
  - Do NOT manually mount Secrets Manager values into pods (defeats purpose)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: [`terraform-style-guide`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 5)
  - **Parallel Group**: Wave 5 — with T13, T14, T15, T16, T18, T19
  - **Blocks**: T23 (ExternalSecret CRs in K8s manifests need this operator)
  - **Blocked By**: T5 (IRSA), T7 (secrets exist), T11 (nodes)

  **References**:
  - **Pattern References**: `terraform-style-guide` skill
  - **External References**:
    - External Secrets Operator: `https://external-secrets.io/latest/provider/aws-secrets-manager/`
  - **WHY Each Reference Matters**:
    - ClusterSecretStore + IRSA is the production pattern for sharing AWS secret access across namespaces

  **Acceptance Criteria**:
  - [ ] `terraform validate` + `fmt -check` pass
  - [ ] `kubectl get crd | grep external-secrets.io` returns >= 4 CRDs
  - [ ] `kubectl get clustersecretstore aws-secretsmanager -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` returns `True`

  **QA Scenarios**:

  ```
  Scenario: ESO running, ClusterSecretStore Ready
    Tool: interactive_bash
    Preconditions: T5 IRSA re-applied; T7, T11 done
    Steps:
      1. tmux: `cd infra/envs/staging && terraform apply -target=module.external_secrets -auto-approve`
      2. tmux: `kubectl wait --for=condition=Available deployment/external-secrets -n external-secrets --timeout=180s`
      3. tmux: `kubectl get clustersecretstore aws-secretsmanager -o yaml | tee /tmp/css.yaml`
      4. Assert: status.conditions has type=Ready, status=True
      5. tmux: create test ExternalSecret to fetch a Secrets Manager value, verify K8s Secret materializes within 30s
    Expected Result: ESO operational, ClusterSecretStore Ready, test ExternalSecret syncs
    Failure Indicators: ClusterSecretStore status NOT Ready, AccessDenied in eso logs
    Evidence: docs/evidence/03-k8s/external-secrets.txt + .sisyphus/evidence/task-17-css.yaml
  ```

  **Evidence to Capture**:
  - [ ] task-17-css.yaml — ClusterSecretStore status
  - [ ] docs/evidence/03-k8s/external-secrets.txt — operator validation

  **Commit**: YES (single commit)
  - Message: `feat(infra/modules/external-secrets): eso with clustersecretstore for aws secretsmanager`
  - Files: `infra/modules/external-secrets/*`
  - Pre-commit: `terraform_fmt`, `terraform_validate`, `gitleaks`

- [x] 18. **metrics-server install (HPA prerequisite)**

  **What to do**:
  - Create `infra/modules/metrics-server/{main.tf,variables.tf,outputs.tf,versions.tf,README.md}`
  - Resources:
    - `helm_release.metrics_server` — chart `metrics-server`, repository `https://kubernetes-sigs.github.io/metrics-server/`, version `3.12.1` (pin), namespace `kube-system`
    - Default values are fine (no `--kubelet-insecure-tls` needed on EKS AL2023)
  - Variables: `chart_version` (default `3.12.1`)
  - Outputs: helm release status

  **Must NOT do**:
  - Do NOT use `--kubelet-insecure-tls` (EKS AL2023 has valid kubelet certs)
  - Do NOT skip — without metrics-server, HPA `kubectl top` and resource-based autoscaling don't work, breaking PDF "scaling testing" requirement

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`terraform-style-guide`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 5)
  - **Parallel Group**: Wave 5 — with T13, T14, T15, T16, T17, T19
  - **Blocks**: T29 (HPA load test needs metrics)
  - **Blocked By**: T11

  **References**:
  - **Pattern References**: `terraform-style-guide` skill
  - **External References**:
    - metrics-server: `https://github.com/kubernetes-sigs/metrics-server`
  - **WHY Each Reference Matters**:
    - HPA polls metrics-server; without it HPA stays in `<unknown>/<target>` state and never scales

  **Acceptance Criteria**:
  - [ ] `terraform validate` + `fmt -check` pass
  - [ ] `kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'` returns `True`
  - [ ] `kubectl top nodes` returns CPU/memory data (not error)

  **QA Scenarios**:

  ```
  Scenario: metrics-server installed and serving metrics
    Tool: interactive_bash
    Preconditions: T11 done
    Steps:
      1. tmux: `cd infra/envs/staging && terraform apply -target=module.metrics_server -auto-approve`
      2. tmux: `kubectl wait --for=condition=Available deployment/metrics-server -n kube-system --timeout=120s`
      3. tmux: `for i in {1..12}; do kubectl top nodes 2>/dev/null && break; sleep 5; done | tee /tmp/top.txt`
      4. Assert: `grep -E "^[a-z0-9-]+\.ec2\.internal" /tmp/top.txt | wc -l` >= 2
    Expected Result: kubectl top nodes returns metrics for all nodes within 60s
    Failure Indicators: APIService not Available; kubectl top errors
    Evidence: docs/evidence/03-k8s/metrics-server.txt + .sisyphus/evidence/task-18-validation.txt
  ```

  **Evidence to Capture**:
  - [ ] task-18-validation.txt — top nodes output
  - [ ] docs/evidence/03-k8s/metrics-server.txt — APIService status

  **Commit**: YES (single commit)
  - Message: `feat(infra/modules/metrics-server): hpa prerequisite via helm`
  - Files: `infra/modules/metrics-server/*`
  - Pre-commit: `terraform_fmt`, `terraform_validate`, `gitleaks`

- [x] 19. **Namespaces + base RBAC: weather-staging, weather-prod**

  **What to do**:
  - Create `infra/modules/namespaces/{main.tf,variables.tf,outputs.tf,versions.tf,README.md}`
  - Resources (use `kubernetes_namespace_v1`):
    - Namespace `weather-staging` with labels `{ env = "staging", managed-by = "terraform" }`
    - Namespace `weather-prod` with labels `{ env = "prod", managed-by = "terraform" }`
    - `kubernetes_resource_quota_v1` per namespace: requests.cpu 4, requests.memory 8Gi, limits.cpu 8, limits.memory 16Gi, pods 50
    - `kubernetes_limit_range_v1` per namespace: default container request 100m/128Mi, limit 500m/512Mi
    - `kubernetes_network_policy_v1` per namespace: deny-all-ingress baseline + allow-from-ingress-nginx
  - Variables: `cluster_name`
  - Outputs: namespace names

  **Must NOT do**:
  - Do NOT skip resource quotas (single cluster shared across envs needs guardrails)
  - Do NOT skip NetworkPolicy baseline (defense in depth; though VPC CNI lacks enforcement by default — documented)
  - Do NOT use deprecated `kubernetes_namespace` (use v1 suffixed resource)

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`terraform-style-guide`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 5)
  - **Parallel Group**: Wave 5 — with T13, T14, T15, T16, T17, T18
  - **Blocks**: T23 (K8s manifests deploy into these namespaces)
  - **Blocked By**: T11, T12 (need cluster + access)

  **References**:
  - **Pattern References**: `terraform-style-guide` skill
  - **External References**:
    - kubernetes provider: `https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs`
  - **WHY Each Reference Matters**:
    - Resource quotas prevent one env from starving the other on a shared cluster

  **Acceptance Criteria**:
  - [ ] `terraform validate` + `fmt -check` pass
  - [ ] `kubectl get ns weather-staging weather-prod -o jsonpath='{.items[*].metadata.labels.env}'` returns `staging prod`
  - [ ] `kubectl get resourcequota -n weather-staging` returns 1 quota
  - [ ] `kubectl get networkpolicy -n weather-staging` returns >= 2 policies

  **QA Scenarios**:

  ```
  Scenario: Namespaces + quotas + network policies created
    Tool: Bash
    Preconditions: T11, T12 done
    Steps:
      1. `cd infra/envs/staging && terraform apply -target=module.namespaces -auto-approve`
      2. `kubectl get ns weather-staging weather-prod -o json | jq -r '.items[].metadata.labels.env'` → assert "staging" + "prod"
      3. `for ns in weather-staging weather-prod; do kubectl get resourcequota,limitrange,networkpolicy -n $ns; done | tee /tmp/ns-objs.txt`
      4. Assert: each ns has 1 resourcequota + 1 limitrange + >= 2 networkpolicy
    Expected Result: 2 namespaces with quotas, limit ranges, network policies
    Evidence: docs/evidence/03-k8s/namespaces.txt + .sisyphus/evidence/task-19-validation.txt
  ```

  **Evidence to Capture**:
  - [ ] task-19-validation.txt — namespace + objects listing
  - [ ] docs/evidence/03-k8s/namespaces.txt

  **Commit**: YES (single commit)
  - Message: `feat(infra/modules/namespaces): weather-staging + weather-prod with quotas, limits, netpol`
  - Files: `infra/modules/namespaces/*`
  - Pre-commit: `terraform_fmt`, `terraform_validate`, `gitleaks`

- [x] 20. **Weather API Node.js application (Express + supertest)**

  **What to do**:
  - Create directory `app/` with:
    - `package.json` — name `weather-api`, scripts: `start`, `dev`, `test`, `lint`; deps: `express ^4.21`, `pino ^9`, `pino-http ^10`, `node-fetch ^3`; devDeps: `jest ^29`, `supertest ^7`, `eslint ^9`
    - `src/server.js` — Express app, middleware (`pino-http`, JSON), routes:
      - `GET /healthz` → `{ status: "ok" }` (no auth, used by k8s liveness/readiness)
      - `GET /weather?latitude=<n>&longitude=<n>` → proxy to Open-Meteo `https://api.open-meteo.com/v1/forecast?latitude=<>&longitude=<>&current_weather=true`; return JSON unchanged with added `_meta: { source: "open-meteo", request_id }`
      - `GET /version` → `{ version: process.env.APP_VERSION || 'dev', commit: process.env.GIT_SHA || 'local' }`
    - `src/config.js` — load `WEATHER_API_BASE` (default `https://api.open-meteo.com/v1`), `LOG_LEVEL` (default `info`), `PORT` (default `8080`) from env
    - `src/logger.js` — pino instance, JSON output to stdout (Fluent Bit will ship)
    - `src/__tests__/server.test.js` — supertest tests:
      - `GET /healthz` returns 200 and `{ status: "ok" }`
      - `GET /version` returns 200 with `version` field
      - `GET /weather?latitude=21.03&longitude=105.85` (mock fetch) returns 200 with `current_weather`
      - `GET /weather` without lat/lon returns 400
    - `.eslintrc.json`, `jest.config.js`, `.dockerignore` (exclude node_modules, .git, tests, README)
    - `README.md` (English) — local run, env vars, API docs

  **Must NOT do**:
  - Do NOT implement auth in the app (auth is at API Gateway via Lambda authorizer per architecture)
  - Do NOT log secrets / Authorization header
  - Do NOT use synchronous fs/network APIs
  - Do NOT include console.log; use pino only

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Greenfield Node.js app with tests; needs care for logging, error handling, dockerization later.
  - **Skills**: [] (no domain skill required)

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 6)
  - **Parallel Group**: Wave 6 — with T21, T22
  - **Blocks**: T21 (Dockerfile builds this), T23 (K8s Deployment runs image)
  - **Blocked By**: T1 (gitignore prevents node_modules commits)

  **References**:
  - **Pattern References**: analysis doc §5 (auth flow shows where app sits — behind authorizer)
  - **External References**:
    - Open-Meteo API: `https://open-meteo.com/en/docs`
    - Pino logger: `https://getpino.io/`
    - Supertest: `https://github.com/ladjs/supertest`
  - **WHY Each Reference Matters**:
    - Open-Meteo no-key API removes a config dimension; perfect for assessment scope
    - Pino JSON output integrates cleanly with Fluent Bit/CloudWatch (vs unstructured console.log)

  **Acceptance Criteria**:
  - [ ] `cd app && npm ci && npm test` exits 0; >= 4 tests pass
  - [ ] `npm run lint` exits 0
  - [ ] Local run: `node src/server.js` starts on port 8080; `curl http://localhost:8080/healthz` returns `{"status":"ok"}`
  - [ ] No `console.log` in src/ (use grep `grep -rn "console.log" app/src && exit 1 || exit 0`)

  **QA Scenarios**:

  ```
  Scenario: App starts, healthz works, weather proxy works
    Tool: interactive_bash
    Preconditions: T1 done; npm available
    Steps:
      1. tmux: `cd app && npm ci 2>&1 | tail -5`
      2. tmux: `npm test 2>&1 | tee /tmp/app-tests.txt`
      3. Assert: `grep -E "Tests:.*passed" /tmp/app-tests.txt`
      4. tmux: `npm run lint`
      5. tmux background: `node src/server.js &` (PID captured)
      6. tmux: `sleep 2 && curl -sf http://localhost:8080/healthz | jq -e '.status == "ok"'`
      7. tmux: `curl -sf "http://localhost:8080/weather?latitude=21.03&longitude=105.85" | jq -e '.current_weather.temperature' | tee /tmp/weather.json`
      8. tmux: `curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/weather"` → assert "400"
      9. tmux: kill server, save logs
    Expected Result: All tests pass, healthz/version/weather endpoints work, missing params returns 400
    Failure Indicators: tests fail, lint errors, weather call returns non-200, healthz unreachable
    Evidence: docs/evidence/05-app/local-test.txt + .sisyphus/evidence/task-20-weather-sample.json

  Scenario: Logging is structured JSON
    Tool: Bash
    Steps:
      1. `cd app && node -e "require('./src/logger.js').info({test: 'hello'}, 'msg')" 2>&1 | jq -e '.test == "hello"'`
    Expected Result: Single JSON line on stdout
    Evidence: .sisyphus/evidence/task-20-log-format.json
  ```

  **Evidence to Capture**:
  - [ ] task-20-weather-sample.json — Open-Meteo response sample
  - [ ] task-20-log-format.json — pino JSON proof
  - [ ] docs/evidence/05-app/local-test.txt — test/lint output

  **Commit**: YES (single commit)
  - Message: `feat(app): weather api with healthz, version, weather proxy + supertest`
  - Files: `app/{package.json,src/**,*.config.js,.eslintrc.json,.dockerignore,README.md}`
  - Pre-commit: `eslint`, `prettier`, `gitleaks` (no `terraform_*` for this dir)

- [x] 21. **Multi-stage Dockerfile for weather-api (multi-arch hint via buildx)**

  **What to do**:
  - Create `app/Dockerfile` (multi-stage):
    ```
    # syntax=docker/dockerfile:1.7
    FROM node:20-alpine AS deps
    WORKDIR /app
    COPY package*.json ./
    RUN npm ci --omit=dev

    FROM node:20-alpine AS runtime
    WORKDIR /app
    RUN addgroup -S app && adduser -S -G app app
    COPY --from=deps /app/node_modules ./node_modules
    COPY src ./src
    COPY package.json ./
    USER app
    EXPOSE 8080
    HEALTHCHECK --interval=30s --timeout=3s --retries=3 CMD wget -q --spider http://localhost:8080/healthz || exit 1
    CMD ["node", "src/server.js"]
    ```
  - Create `app/.dockerignore` (already added in T20 but verify covers `node_modules`, `.git`, `__tests__`, `*.test.js`)
  - Add `Makefile` targets in repo root: `app-build`, `app-run-local`, `app-shell`

  **Must NOT do**:
  - Do NOT run as root (use non-root user `app`)
  - Do NOT include devDependencies in runtime stage
  - Do NOT skip HEALTHCHECK (k8s liveness uses HTTP probe but HEALTHCHECK is good docker hygiene)
  - Do NOT use `:latest` for base image — pin `node:20-alpine`

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Standard Node.js multi-stage Dockerfile.
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 6)
  - **Parallel Group**: Wave 6 — with T20, T22
  - **Blocks**: T24 (build+push needs Dockerfile)
  - **Blocked By**: T20 (needs app/ structure)

  **References**:
  - **Pattern References**: analysis doc §4.4 (containerization)
  - **External References**:
    - Multi-stage builds: `https://docs.docker.com/build/building/multi-stage/`
    - Node.js Docker best practices: `https://github.com/nodejs/docker-node/blob/main/docs/BestPractices.md`
  - **WHY Each Reference Matters**:
    - Multi-stage halves image size (no devDeps, no source maps, no test infra)
    - Non-root user blocks privilege escalation if container compromised

  **Acceptance Criteria**:
  - [ ] `docker build -t weather-api:test app/` succeeds
  - [ ] Image size < 200MB: `docker images weather-api:test --format '{{.Size}}'`
  - [ ] Image runs as non-root: `docker run --rm weather-api:test id` shows `uid=...(app)` not root
  - [ ] HEALTHCHECK works: `docker inspect weather-api:test --format='{{.Config.Healthcheck.Test}}'` non-empty

  **QA Scenarios**:

  ```
  Scenario: Image builds, runs as non-root, serves healthz
    Tool: interactive_bash
    Preconditions: T20 done, docker installed
    Steps:
      1. tmux: `docker build -t weather-api:test app/ 2>&1 | tail -10`
      2. tmux: `docker images weather-api:test --format '{{.Size}}' | tee /tmp/size.txt`
      3. Assert: parse size, < 200MB
      4. tmux: `docker run --rm weather-api:test id | grep -q "uid=.*(app)"`
      5. tmux background: `docker run --rm -d -p 18080:8080 --name wa-test weather-api:test`
      6. tmux: `sleep 3 && curl -sf http://localhost:18080/healthz | jq -e '.status == "ok"'`
      7. tmux: `docker stop wa-test`
    Expected Result: Image builds < 200MB, runs as `app` user, healthz responds
    Failure Indicators: build fails, image > 200MB, runs as root, healthz unreachable
    Evidence: docs/evidence/05-app/docker-build.txt + .sisyphus/evidence/task-21-image.txt
  ```

  **Evidence to Capture**:
  - [ ] task-21-image.txt — image size + user proof
  - [ ] docs/evidence/05-app/docker-build.txt — build log

  **Commit**: YES (single commit)
  - Message: `feat(app): multi-stage dockerfile, non-root user, healthcheck`
  - Files: `app/Dockerfile`, `app/.dockerignore` (if not in T20)
  - Pre-commit: `hadolint` (if installed), `gitleaks`

- [x] 22. **Lambda authorizer Node.js code (JWT verify against Cognito JWKS)**

  **What to do**:
  - Create directory `lambda-authorizer/` with:
    - `package.json` — name `max-weather-authorizer`, deps: `jsonwebtoken ^9.0.2`, `jwks-rsa ^3.1.0`; devDeps: `jest ^29`
    - `src/index.js` — exports `handler(event)` for API Gateway TOKEN authorizer (or REQUEST authorizer; choose TOKEN — simpler):
      ```
      Steps:
      1. Extract `event.authorizationToken` (format: "Bearer <jwt>")
      2. Strip "Bearer " prefix; if missing, throw "Unauthorized"
      3. Decode JWT header to get `kid`
      4. Fetch JWKS from `process.env.JWKS_URI` (cached via jwks-rsa)
      5. Verify signature, issuer (`process.env.ISSUER`), token_use=`access`, scope contains `weather-api/read`
      6. On success: return IAM policy { principalId: client_id, policyDocument: { Statement: [{ Effect: "Allow", Action: "execute-api:Invoke", Resource: event.methodArn }] }, context: { client_id } }
      7. On failure: throw "Unauthorized" (API GW returns 401)
      ```
    - `src/__tests__/index.test.js` — jest tests with mocked JWKS:
      - valid token → returns Allow policy
      - missing Bearer → throws Unauthorized
      - wrong issuer → throws Unauthorized
      - wrong scope → throws Unauthorized (returns Deny or throws — test asserts behavior)
      - expired token → throws Unauthorized
    - `Makefile` snippet for build: `make authorizer-build` → `cd lambda-authorizer && npm ci --omit=dev && zip -qr ../dist/lambda-authorizer.zip .`

  **Must NOT do**:
  - Do NOT skip signature verification (just decoding without verify is the classic JWT bug)
  - Do NOT hardcode JWKS URI / issuer (use env vars, set by Terraform Lambda env)
  - Do NOT log token contents (PII / security)
  - Do NOT bundle devDependencies in the zip

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Security-critical code; JWT verification subtleties.
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 6)
  - **Parallel Group**: Wave 6 — with T20, T21
  - **Blocks**: T24 (zip → upload to Lambda), T28 (API GW wires to authorizer)
  - **Blocked By**: T1, T6 (ECR repo for authorizer image — actually we use ZIP package not container image; ECR repo is unused for authorizer; remove from T6 OR keep optional). Simpler: ZIP deploy. Mark ECR `lambda-authorizer` repo as YAGNI (decision recorded — remove from T6).

  **References**:
  - **Pattern References**: analysis doc §5 (auth flow)
  - **External References**:
    - jsonwebtoken: `https://github.com/auth0/node-jsonwebtoken#readme`
    - jwks-rsa with caching: `https://github.com/auth0/node-jwks-rsa#readme`
    - API Gateway TOKEN authorizer event: `https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-lambda-authorizer-input.html`
  - **WHY Each Reference Matters**:
    - jwks-rsa rate-limit + cache reduces JWKS fetches per cold start; without it, API GW gets slow first request after warm
    - TOKEN vs REQUEST authorizer event shape differs — wrong shape = silent auth bypass risk

  **Acceptance Criteria**:
  - [ ] `cd lambda-authorizer && npm ci && npm test` exits 0; >= 5 tests pass
  - [ ] `make authorizer-build` produces `dist/lambda-authorizer.zip` < 5MB
  - [ ] Local hand-test with real Cognito token works (run handler with mocked event in REPL)

  **QA Scenarios**:

  ```
  Scenario: Authorizer accepts valid token, rejects invalid
    Tool: interactive_bash
    Preconditions: T9 done (real Cognito token available)
    Steps:
      1. tmux: `cd lambda-authorizer && npm ci && npm test 2>&1 | tee /tmp/auth-tests.txt`
      2. Assert: `grep -E "Tests:.*passed" /tmp/auth-tests.txt`
      3. tmux: get real token via T9 procedure → `TOKEN=$(...)`
      4. tmux: write small REPL script:
         ```
         JWKS_URI=$(cd ../infra/envs/staging && terraform output -raw cognito_jwks_uri)
         ISSUER=$(cd ../infra/envs/staging && terraform output -raw cognito_issuer)
         JWKS_URI=$JWKS_URI ISSUER=$ISSUER node -e '
           const h=require("./src/index.js").handler;
           h({authorizationToken:"Bearer '"$TOKEN"'", methodArn:"arn:aws:execute-api:us-east-1:123:abc/staging/GET/weather"})
             .then(r=>{console.log(JSON.stringify(r));process.exit(0)})
             .catch(e=>{console.error(e.message);process.exit(1)})'
         ```
      5. Assert: outputs `{"principalId":...,"policyDocument":{"Statement":[{"Effect":"Allow"`
      6. tmux: rerun with garbage token → assert exit 1 with "Unauthorized"
    Expected Result: Real Cognito token → Allow policy; bogus token → Unauthorized
    Failure Indicators: jest fails, real token rejected (config wrong), bogus token accepted (BIG security bug)
    Evidence: docs/evidence/06-lambda/authorizer-test.txt + .sisyphus/evidence/task-22-real-token.txt
  ```

  **Evidence to Capture**:
  - [ ] task-22-real-token.txt — real-token Allow proof + bogus-token Deny proof
  - [ ] docs/evidence/06-lambda/authorizer-test.txt — jest output

  **Commit**: YES (single commit)
  - Message: `feat(lambda-authorizer): jwt verify against cognito jwks with scope check`
  - Files: `lambda-authorizer/{package.json,src/**,Makefile}`
  - Pre-commit: `eslint`, `gitleaks`

  **Note on T6 (ECR for authorizer)**: Since we deploy authorizer as ZIP, the `max-weather/lambda-authorizer` ECR repo is unused. **Decision**: KEEP it in T6 for symmetry (negligible cost, no images = no storage charge), but document it as "reserved for future container-based authorizer migration". Update T6 README accordingly during execution.

- [x] 23. **Kubernetes manifests: ServiceAccount, ExternalSecret, Deployment, Service, Ingress, HPA, PDB**

  **What to do**:
  - Create directory `k8s/` with **base** and **overlays** structure (Kustomize):
    - `k8s/base/`:
      - `serviceaccount.yaml` — `weather-api` SA with annotation `eks.amazonaws.com/role-arn: <wired by overlay>`
      - `externalsecret.yaml` — `ExternalSecret` named `weather-app-config`, refresh 1h, sources from `aws-secretsmanager` ClusterSecretStore, key `max-weather/<env>/app-config`, target K8s Secret `weather-app-config`
      - `deployment.yaml` — Deployment `weather-api`, 2 replicas, container image `<wired>`, port 8080, envFrom `weather-app-config` Secret, env GIT_SHA from downward, resources requests cpu=100m memory=128Mi limits cpu=500m memory=256Mi, livenessProbe HTTP /healthz on 8080 initial 10s period 10s, readinessProbe HTTP /healthz on 8080 initial 5s period 5s, securityContext runAsNonRoot=true runAsUser=1000 readOnlyRootFilesystem=true allowPrivilegeEscalation=false capabilities.drop=[ALL], serviceAccountName weather-api, topology spread constraints across `topology.kubernetes.io/zone`
      - `service.yaml` — ClusterIP svc `weather-api` port 80 → targetPort 8080
      - `ingress.yaml` — Ingress `weather-api`, ingressClassName: nginx, host `<env>.max-weather.local` (resolved via /etc/hosts for testing) AND a path-based fallback for NLB direct access; rules path `/` → svc weather-api:80
      - `hpa.yaml` — HorizontalPodAutoscaler `weather-api`, minReplicas 2, maxReplicas 10, metrics: type Resource cpu averageUtilization 60%, behavior scaleUp.stabilizationWindowSeconds 0, scaleDown.stabilizationWindowSeconds 300
      - `pdb.yaml` — PodDisruptionBudget `weather-api`, minAvailable 1
      - `kustomization.yaml` — list all base resources
    - `k8s/overlays/staging/`:
      - `kustomization.yaml` — namespace weather-staging, namePrefix none, images: weather-api → `<ECR_URL>:staging-<sha>`, patchesStrategicMerge for serviceaccount role ARN (staging IRSA from T5), externalsecret target name suffix
      - `serviceaccount-patch.yaml` — sets correct IRSA role ARN
    - `k8s/overlays/prod/`:
      - same structure, namespace weather-prod, prod IRSA role, image `<ECR_URL>:prod-<sha>`, replicas 3 (override), HPA min 3 / max 10 (override)

  **Must NOT do**:
  - Do NOT use raw YAML duplication for envs — Kustomize overlays only
  - Do NOT skip securityContext (security baseline)
  - Do NOT use `latest` tag in overlays — explicit `staging-<sha>` and `prod-<sha>`
  - Do NOT skip PDB (rolling update + voluntary disruption safety)
  - Do NOT hardcode ECR URL — use Kustomize image transformation

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: K8s manifest correctness has many subtle pitfalls (probe paths, kustomize patches, IRSA wiring).
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO (depends on many things; treat as Wave 7 sequential)
  - **Parallel Group**: Wave 7 — paired with T24 (T23 authors manifests, T24 builds images; both must finish before deployment)
  - **Blocks**: T26 (Jenkinsfile uses `kubectl apply -k`), T29 (load test on running app)
  - **Blocked By**: T13 (IngressClass nginx), T17 (ESO), T19 (namespaces), T5 (IRSA), T6 (ECR URLs)

  **References**:
  - **Pattern References**: analysis doc §4.4 (k8s layer)
  - **External References**:
    - Kustomize image transformer: `https://kubectl.docs.kubernetes.io/references/kustomize/builtins/#_imagetagtransformer_`
    - Pod security baseline: `https://kubernetes.io/docs/concepts/security/pod-security-standards/`
    - ExternalSecret spec: `https://external-secrets.io/latest/api/externalsecret/`
  - **WHY Each Reference Matters**:
    - Kustomize image transformer is the only clean way to swap image tags per overlay without sed
    - PSA `restricted` requires runAsNonRoot, drop ALL caps, etc. — without these, future cluster-wide PSA enforcement breaks pods

  **Acceptance Criteria**:
  - [ ] `kubectl kustomize k8s/overlays/staging` produces valid YAML (no errors)
  - [ ] `kubectl kustomize k8s/overlays/prod` produces valid YAML
  - [ ] `kubeconform` (or `kubectl --dry-run=client apply -f -`) passes for both overlays
  - [ ] After apply: `kubectl get deploy/svc/ingress/hpa/pdb -n weather-staging -l app=weather-api` shows all 5 objects
  - [ ] HPA reports `currentReplicas` and `desiredReplicas` (not `<unknown>`) within 60s of pod ready

  **QA Scenarios**:

  ```
  Scenario: Manifests deploy successfully to staging
    Tool: interactive_bash
    Preconditions: T13, T17, T19 done; T24 produced images in ECR
    Steps:
      1. tmux: `kubectl kustomize k8s/overlays/staging | tee /tmp/staging.yaml`
      2. tmux: `kubeconform -summary /tmp/staging.yaml || kubectl apply --dry-run=client -f /tmp/staging.yaml`
      3. tmux: `kubectl apply -k k8s/overlays/staging`
      4. tmux: `kubectl rollout status deployment/weather-api -n weather-staging --timeout=180s`
      5. tmux: `kubectl get pods -n weather-staging -l app=weather-api -o jsonpath='{.items[*].status.phase}'` → assert all "Running"
      6. tmux: port-forward and test: `kubectl port-forward -n weather-staging svc/weather-api 18080:80 &`
      7. tmux: `sleep 3 && curl -sf http://localhost:18080/healthz | jq -e '.status == "ok"'`
      8. tmux: `kubectl get hpa weather-api -n weather-staging -o jsonpath='{.status.currentMetrics}'` → not empty after 60s
    Expected Result: All resources apply, pods Running, healthz works, HPA has metrics
    Failure Indicators: rollout times out, HPA shows <unknown>/60% (metrics-server issue), ExternalSecret not Ready
    Evidence: docs/evidence/03-k8s/staging-manifests-applied.txt + .sisyphus/evidence/task-23-deploy.txt

  Scenario: ExternalSecret materializes K8s Secret
    Tool: Bash
    Steps:
      1. `kubectl get externalsecret weather-app-config -n weather-staging -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` → "True"
      2. `kubectl get secret weather-app-config -n weather-staging -o jsonpath='{.data}' | base64 -d 2>/dev/null || true` (just check presence)
      3. Assert: `kubectl get secret weather-app-config -n weather-staging` succeeds
    Evidence: .sisyphus/evidence/task-23-externalsecret.txt
  ```

  **Evidence to Capture**:
  - [ ] task-23-deploy.txt — staging rollout + healthz proof
  - [ ] task-23-externalsecret.txt — ExternalSecret Ready proof
  - [ ] docs/evidence/03-k8s/staging-manifests-applied.txt — full apply log

  **Commit**: YES (single commit)
  - Message: `feat(k8s): kustomize base + staging/prod overlays with deployment, svc, ingress, hpa, pdb, externalsecret`
  - Files: `k8s/base/*.yaml`, `k8s/overlays/staging/*.yaml`, `k8s/overlays/prod/*.yaml`
  - Pre-commit: `kubeconform` (if installed), `gitleaks`

- [x] 24. **Build + push images: weather-api → ECR; package + upload Lambda authorizer ZIP**

  **What to do**:
  - Add to root `Makefile`:
    ```
    REGION ?= us-east-1
    APP_REPO := $(shell cd infra/envs/staging && terraform output -raw weather_api_repository_url)
    GIT_SHA := $(shell git rev-parse --short HEAD)

    .PHONY: ecr-login app-build-push authorizer-package authorizer-deploy

    ecr-login:
        aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $$(echo $(APP_REPO) | cut -d/ -f1)

    app-build-push: ecr-login
        docker buildx build --platform linux/amd64 -t $(APP_REPO):staging-$(GIT_SHA) -t $(APP_REPO):latest --push app/

    authorizer-package:
        cd lambda-authorizer && rm -rf node_modules dist && npm ci --omit=dev
        mkdir -p dist
        cd lambda-authorizer && zip -qr ../dist/lambda-authorizer.zip src/ node_modules/ package.json

    authorizer-deploy: authorizer-package
        aws lambda update-function-code --function-name max-weather-authorizer --zip-file fileb://dist/lambda-authorizer.zip --region $(REGION)
        aws lambda wait function-updated --function-name max-weather-authorizer --region $(REGION)
    ```
  - Wire into Jenkins later (T26)
  - First-time manual run produces:
    - ECR image with tag `staging-<sha>` and `latest`
    - Lambda function code updated from placeholder to real authorizer

  **Must NOT do**:
  - Do NOT use docker push without buildx (multi-arch hint reduces "wrong arch" risk)
  - Do NOT bundle node_modules with devDeps in Lambda zip
  - Do NOT push to `latest` for prod (prod uses `prod-<sha>` only)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Mostly orchestration; verification matters more than authoring.
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 7, but FINISHES after T23 since image must exist for T23 deploy)
  - **Parallel Group**: Wave 7 — with T23 (T23 authors manifests in parallel; deployment happens after BOTH done)
  - **Blocks**: T23 deployment step (needs image present), T28 (API GW authorizer wiring needs Lambda updated)
  - **Blocked By**: T6 (ECR repos), T20 (app source), T21 (Dockerfile), T22 (authorizer code)

  **References**:
  - **Pattern References**: Makefile pattern; analysis doc §4.4
  - **External References**:
    - ECR push commands: `https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html`
    - Lambda update-function-code: `https://docs.aws.amazon.com/cli/latest/reference/lambda/update-function-code.html`
  - **WHY Each Reference Matters**:
    - ECR auth token expires (12h); pipeline must re-login each run
    - Lambda update-function-code is async; `wait function-updated` blocks until ready (else next call may hit old code)

  **Acceptance Criteria**:
  - [ ] `make app-build-push` succeeds; `aws ecr describe-images --repository-name max-weather/weather-api --query 'imageDetails[?contains(imageTags, `staging-'`$(git rev-parse --short HEAD)`'`)] | length(@)' --output text` returns `1`
  - [ ] `make authorizer-deploy` succeeds; `aws lambda get-function --function-name max-weather-authorizer --query 'Configuration.LastUpdateStatus' --output text` returns `Successful`

  **QA Scenarios**:

  ```
  Scenario: Image pushed to ECR with correct tag
    Tool: interactive_bash
    Preconditions: T6, T20, T21 done
    Steps:
      1. tmux: `make app-build-push 2>&1 | tee /tmp/push.log`
      2. tmux: `SHA=$(git rev-parse --short HEAD); aws ecr describe-images --repository-name max-weather/weather-api --query "imageDetails[?contains(imageTags, 'staging-$SHA')] | length(@)" --output text` → assert "1"
      3. tmux: `aws ecr describe-images --repository-name max-weather/weather-api --query "imageDetails[?contains(imageTags, 'staging-$SHA')].imageScanFindingsSummary" --output json | tee /tmp/scan.json` (waits for scan)
    Expected Result: Image present in ECR with correct tag, scan completed (HIGH/CRITICAL count = 0 ideal)
    Evidence: docs/evidence/05-app/ecr-push.txt + .sisyphus/evidence/task-24-image.json

  Scenario: Lambda authorizer updated from ZIP
    Tool: interactive_bash
    Preconditions: T22 done; placeholder Lambda exists (created in Terraform — see T28 prereq, but actually Lambda is created in T28; chicken-and-egg). RESOLUTION: T28 creates Lambda function (Terraform) with placeholder index.js inline; T24 then `update-function-code` replaces it.
    Steps:
      1. tmux: `make authorizer-package 2>&1 | tail -5`
      2. tmux: `ls -lh dist/lambda-authorizer.zip` → assert < 5MB
      3. tmux: `make authorizer-deploy 2>&1 | tee /tmp/lambda-deploy.log`
      4. tmux: `aws lambda get-function --function-name max-weather-authorizer --query 'Configuration.LastUpdateStatus' --output text` → assert "Successful"
      5. tmux: `aws lambda invoke --function-name max-weather-authorizer --payload '{"authorizationToken":"Bearer bogus","methodArn":"arn:aws:execute-api:us-east-1:123:abc/staging/GET/weather"}' --cli-binary-format raw-in-base64-out /tmp/lambda-out.json && cat /tmp/lambda-out.json` → returns Unauthorized error (proves real code runs)
    Expected Result: Real authorizer code running in Lambda; bogus token rejected
    Failure Indicators: zip > 5MB, update fails, invoke returns "ok" for bogus token
    Evidence: .sisyphus/evidence/task-24-lambda-invoke.json + docs/evidence/06-lambda/authorizer-deployed.txt
  ```

  **Evidence to Capture**:
  - [ ] task-24-image.json — ECR image with scan findings
  - [ ] task-24-lambda-invoke.json — Lambda invoke proof (bogus rejected)
  - [ ] docs/evidence/05-app/ecr-push.txt — push log
  - [ ] docs/evidence/06-lambda/authorizer-deployed.txt — deploy log

  **Commit**: YES (single commit)
  - Message: `feat(build): makefile targets for ecr push and lambda authorizer deploy`
  - Files: `Makefile` (additions to T1's skeleton)
  - Pre-commit: `gitleaks`

- [x] 25. **Jenkins EC2 module: t3.medium with IAM instance profile, Docker, kubectl, helm, awscli**

  **What to do**:
  - Create `infra/modules/jenkins/{main.tf,variables.tf,outputs.tf,versions.tf,user-data.sh,README.md}`
  - Resources:
    - `aws_security_group.jenkins` — ingress 8080 from `var.allowed_cidrs` (user IP /32, NOT 0.0.0.0/0); egress all
    - `aws_instance.jenkins` — `t3.medium`, AMI `data.aws_ami` Ubuntu 22.04 LTS amd64 latest, key_name from variable (REQUIRED — assumes user has uploaded key pair), iam_instance_profile from T5 output, subnet_id = first public subnet, root_block_device 30GB gp3 encrypted, user_data = file `user-data.sh`, tags `{ Name = max-weather-jenkins }`
    - `aws_eip.jenkins` (optional but recommended for stable URL during demo)
    - `user-data.sh` (executes on first boot):
      ```
      #!/bin/bash
      set -e
      apt-get update -y
      apt-get install -y openjdk-17-jre git curl unzip docker.io
      systemctl enable --now docker
      usermod -aG docker ubuntu
      # awscli v2
      curl -sf https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscli.zip
      unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install
      # kubectl 1.30
      curl -sLO https://dl.k8s.io/release/v1.30.6/bin/linux/amd64/kubectl
      install -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl
      # helm 3
      curl -sf https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
      # Jenkins (LTS)
      curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
      echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
      apt-get update -y
      apt-get install -y jenkins
      usermod -aG docker jenkins
      systemctl enable --now jenkins
      # Save initial admin password to known location (operator fetches via SSM/console)
      sleep 30 && cp /var/lib/jenkins/secrets/initialAdminPassword /home/ubuntu/initialAdminPassword || true
      chown ubuntu:ubuntu /home/ubuntu/initialAdminPassword || true
      ```
  - Variables: `name_prefix`, `vpc_id`, `public_subnet_id`, `instance_profile_name`, `key_name` (REQUIRED), `allowed_cidrs` (REQUIRED — list of strings)
  - Outputs: `instance_id`, `instance_public_ip`, `instance_public_dns`, `eip_address`

  **Must NOT do**:
  - Do NOT use 0.0.0.0/0 for SG ingress (user IP only)
  - Do NOT skip IAM instance profile (Jenkins MUST use role, not static keys)
  - Do NOT install plugins via user-data (manual install via UI is acceptable for assessment)
  - Do NOT skip docker.io install (Jenkins agent runs builds locally)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: EC2 + user-data + IAM combo with security implications; user-data debugging is painful.
  - **Skills**: [`terraform-style-guide`]

  **Parallelization**:
  - **Can Run In Parallel**: NO (depends on T5 + T4)
  - **Parallel Group**: Wave 8 — sequential before T26
  - **Blocks**: T26 (Jenkinsfile runs on this)
  - **Blocked By**: T4 (subnet), T5 (instance profile), T1 (gitignore for terraform)

  **References**:
  - **Pattern References**: `terraform-style-guide` skill; analysis doc §4.4 (Jenkins layer)
  - **External References**:
    - Jenkins Debian install: `https://www.jenkins.io/doc/book/installing/linux/#debianubuntu`
    - EC2 instance profile: `https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-ec2_instance-profiles.html`
  - **WHY Each Reference Matters**:
    - Instance profile is the assessment-critical "no static AWS keys" guarantee
    - User-data debugging via `cat /var/log/cloud-init-output.log` only — get the script right first time

  **Acceptance Criteria**:
  - [ ] `terraform validate` + `fmt -check` pass
  - [ ] After apply: `aws ec2 describe-instances --instance-ids $(terraform output -raw instance_id) --query 'Reservations[0].Instances[0].State.Name' --output text` returns `running`
  - [ ] `aws ec2 describe-instances --instance-ids <id> --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' --output text` returns Jenkins instance profile ARN
  - [ ] After ~5 min: `curl -sf http://$JENKINS_IP:8080/login` returns HTML containing "Jenkins"
  - [ ] SSH in (operator IP only) and run `aws sts get-caller-identity` as `jenkins` user → returns Jenkins role ARN

  **QA Scenarios**:

  ```
  Scenario: Jenkins EC2 boots, Jenkins UI reachable, IAM role works
    Tool: interactive_bash
    Preconditions: T4, T5 done; user has key pair uploaded; user IP known
    Steps:
      1. tmux: `MY_IP=$(curl -s https://checkip.amazonaws.com)/32`
      2. tmux: `cd infra/envs/staging && terraform apply -target=module.jenkins -var "operator_cidrs=[\"$MY_IP\"]" -var "key_name=<your-key>" -auto-approve`
      3. tmux: `IP=$(terraform output -raw jenkins_eip_address)`; `aws ec2 wait instance-status-ok --instance-ids $(terraform output -raw jenkins_instance_id)`
      4. tmux: `for i in {1..30}; do curl -sf http://$IP:8080/login >/dev/null && break; sleep 10; done`
      5. tmux: `curl -sf http://$IP:8080/login | grep -q "Jenkins"` → assert
      6. tmux: SSH and verify role: `ssh -i <key>.pem ubuntu@$IP 'sudo -u jenkins aws sts get-caller-identity --query Arn --output text'` → contains "max-weather-jenkins"
      7. tmux: SSH and verify tools: `ssh -i <key>.pem ubuntu@$IP 'docker --version && kubectl version --client && helm version --short && aws --version'`
      8. Save: `terraform output -json > docs/evidence/07-jenkins/jenkins-outputs.json`
    Expected Result: Jenkins boots, UI loads, IAM role assumable, all tools installed
    Failure Indicators: instance status check fails, Jenkins UI not reachable in 5 min, SSH role check returns ec2 role
    Evidence: docs/evidence/07-jenkins/jenkins-outputs.json + .sisyphus/evidence/task-25-jenkins-up.txt
  ```

  **Evidence to Capture**:
  - [ ] task-25-jenkins-up.txt — UI reachable + tool versions
  - [ ] docs/evidence/07-jenkins/jenkins-outputs.json — terraform outputs

  **Commit**: YES (single commit)
  - Message: `feat(infra/modules/jenkins): t3.medium ec2 with iam profile, docker, kubectl, helm`
  - Files: `infra/modules/jenkins/*`
  - Pre-commit: `terraform_fmt`, `terraform_validate`, `gitleaks`

- [x] 26. **Jenkinsfile (Declarative): build → test → push → deploy → smoke test**

  **What to do**:
  - Create `Jenkinsfile` (root) and `ci/jenkins-shared/` (helper scripts):
    ```groovy
    pipeline {
      agent any
      options { timestamps(); buildDiscarder(logRotator(numToKeepStr: '15')); ansiColor('xterm') }
      environment {
        AWS_REGION = 'us-east-1'
        APP_REPO   = sh(returnStdout: true, script: "cd infra/envs/staging && terraform output -raw weather_api_repository_url").trim()
        GIT_SHA    = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
        CLUSTER    = 'max-weather'
        NAMESPACE  = 'weather-staging'
      }
      stages {
        stage('Checkout') { steps { checkout scm } }
        stage('App Lint + Test') {
          steps {
            sh 'cd app && npm ci && npm run lint && npm test'
          }
          post { always { junit allowEmptyResults: true, testResults: 'app/junit.xml' } }
        }
        stage('Authorizer Lint + Test') {
          steps { sh 'cd lambda-authorizer && npm ci && npm test' }
        }
        stage('Build + Push Image') {
          steps {
            sh '''
              aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $(echo $APP_REPO | cut -d/ -f1)
              docker buildx build --platform linux/amd64 -t $APP_REPO:staging-$GIT_SHA --push app/
            '''
          }
        }
        stage('Update Kustomize Image') {
          steps {
            sh '''
              cd k8s/overlays/staging
              kustomize edit set image weather-api=$APP_REPO:staging-$GIT_SHA
            '''
          }
        }
        stage('Deploy to Staging') {
          steps {
            sh '''
              aws eks update-kubeconfig --name $CLUSTER --region $AWS_REGION
              kubectl apply -k k8s/overlays/staging
              kubectl rollout status deployment/weather-api -n $NAMESPACE --timeout=180s
            '''
          }
        }
        stage('Smoke Test (NLB direct)') {
          steps {
            sh '''
              NLB=$(kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
              for i in {1..30}; do
                CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: staging.max-weather.local" http://$NLB/healthz -m 10)
                [ "$CODE" = "200" ] && break
                sleep 5
              done
              [ "$CODE" = "200" ] || (echo "Smoke test failed: $CODE"; exit 1)
            '''
          }
        }
      }
      post {
        success { echo "Build OK: $GIT_SHA → $NAMESPACE" }
        failure { echo "Build FAILED: $GIT_SHA" }
      }
    }
    ```
  - Note: Update Kustomize Image stage commits back the change ONLY if running on a branch with credentials configured; for simplicity, omit auto-commit and instead apply the image directly via `kubectl set image deployment/weather-api weather-api=$APP_REPO:staging-$GIT_SHA -n $NAMESPACE` after `kubectl apply -k`
  - Add `ci/README.md` documenting:
    - Required Jenkins plugins: Pipeline, Git, Docker, AnsiColor, Timestamper
    - Manual setup steps (post-install): unlock with initialAdminPassword, install suggested plugins, create admin user, create Pipeline job pointing to repo

  **Must NOT do**:
  - Do NOT store AWS credentials in Jenkins — IAM instance profile only
  - Do NOT skip rollout-status check (silent failure otherwise)
  - Do NOT push to prod automatically (assessment scope = staging only via Jenkins; prod left for future)
  - Do NOT use scripted Pipeline (declarative is the standard)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Pipeline correctness + plugin requirements + step orchestration.
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO (depends on T25 — Jenkins must be up to test)
  - **Parallel Group**: Wave 8 — sequential after T25
  - **Blocks**: T29 (load test runs against deployed app)
  - **Blocked By**: T20–T24 (everything Pipeline orchestrates), T25 (Jenkins runtime)

  **References**:
  - **Pattern References**: analysis doc §4.4 (CI/CD)
  - **External References**:
    - Jenkins Declarative Pipeline: `https://www.jenkins.io/doc/book/pipeline/syntax/`
    - kubectl rollout status: `https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#rollout`
  - **WHY Each Reference Matters**:
    - Declarative Pipeline is the assessment-expected style; scripted is legacy
    - Without `rollout status`, Pipeline marks build SUCCESS even if pods crash — masks real failures

  **Acceptance Criteria**:
  - [ ] Jenkinsfile present at repo root
  - [ ] `groovy -e "..."` validates Pipeline syntax (or use `jenkins-cli declarative-linter` from inside Jenkins)
  - [ ] Manual run via Jenkins UI completes all stages successfully; final smoke test stage returns HTTP 200
  - [ ] Build artifact: console log captured to `docs/evidence/07-jenkins/build-N-console.log`

  **QA Scenarios**:

  ```
  Scenario: Pipeline runs end-to-end and deploys staging
    Tool: interactive_bash + browser (Playwright)
    Preconditions: T25 done; Jenkins job created (via UI manually); webhook OR manual trigger
    Steps:
      1. interactive_bash: SSH to Jenkins → `sudo systemctl status jenkins` → active
      2. Playwright: navigate to `http://$JENKINS_IP:8080/`, login as admin
      3. Playwright: open job `max-weather-pipeline`, click "Build Now"
      4. Playwright: wait until build status is "Success" (poll every 30s up to 15 min)
      5. Playwright: open Console Output, screenshot, save to `docs/evidence/07-jenkins/build-1-console.png`
      6. interactive_bash: from operator → `kubectl get deploy weather-api -n weather-staging -o jsonpath='{.spec.template.spec.containers[0].image}'` → contains current GIT_SHA
      7. interactive_bash: `NLB=...; curl -sf -H "Host: staging.max-weather.local" http://$NLB/healthz` → 200 + json
    Expected Result: Pipeline succeeds; image in cluster matches commit SHA; smoke test passes
    Failure Indicators: any stage fails, image SHA doesn't match HEAD, smoke test 5xx
    Evidence: docs/evidence/07-jenkins/build-1-console.png + .sisyphus/evidence/task-26-pipeline.txt
  ```

  **Evidence to Capture**:
  - [ ] task-26-pipeline.txt — Pipeline trigger + final status
  - [ ] docs/evidence/07-jenkins/build-1-console.png — full Console Output screenshot

  **Commit**: YES (single commit)
  - Message: `feat(ci): jenkinsfile declarative pipeline (lint, test, build, push, deploy, smoke)`
  - Files: `Jenkinsfile`, `ci/README.md`
  - Pre-commit: `gitleaks`

- [x] 27. **API Gateway HTTP API: manual setup runbook + screenshots evidence**

  **What to do**:
  - Create `docs/api-gateway-runbook.md` with step-by-step instructions (PDF allows manual API Gateway setup):
    - Step 1: AWS Console → API Gateway → Create API → HTTP API → Name `max-weather-api`
    - Step 2: Add integration → HTTP proxy → Method `ANY` → URL `http://<NLB-DNS>/weather/{proxy}` (NLB DNS from `terraform output nginx_nlb_hostname`)
    - Step 3: Configure routes → `ANY /weather/{proxy+}` → Integration target = the HTTP proxy created above
    - Step 4: Create authorizer → Lambda → Select `max-weather-authorizer` → Identity source `$request.header.Authorization` → Response mode SIMPLE → Cache TTL 300s → Authorizer payload v2.0
    - Step 5: Attach authorizer to route `ANY /weather/{proxy+}`
    - Step 6: Create stage `prod` with auto-deploy enabled, default route throttling burst=100 rate=50
    - Step 7: Enable access logging → CloudWatch log group `/aws/apigateway/max-weather-api` (created by T8) → JSON format
    - Step 8: Note Invoke URL → record in `docs/evidence/05-app/api-gateway-invoke-url.txt`
    - Step 9: Test with `curl -H "Authorization: Bearer $TOKEN" $INVOKE_URL/weather/forecast?lat=10.78&lon=106.70` → expect 200 JSON
    - Step 10: Test without token → expect 401 from authorizer
  - Capture screenshots at each step → save to `docs/evidence/05-app/api-gateway-screenshots/step-{NN}-{description}.png`
  - Document rollback: how to delete API Gateway, authorizer attachment
  - Add troubleshooting section: 502 = NLB unreachable / 401 = token expired or wrong scope / 403 = scope missing
  - Add `infra/envs/staging/imported.tf` placeholder with `terraform import` instructions for future codification (out of scope for now, but documented)

  **Must NOT do**:
  - Do NOT use REST API (v1) — must be HTTP API (v2) for Lambda authorizer payload v2.0 simple response mode
  - Do NOT enable mutual TLS (out of scope)
  - Do NOT create custom domain / ACM cert (assessment uses default `*.execute-api.<region>.amazonaws.com` URL)
  - Do NOT hardcode NLB DNS — always derive from `terraform output`
  - Do NOT skip access logging — required for CloudWatch evidence (PDF mandate)
  - Do NOT set authorizer cache TTL > 300s (token might expire)
  - Do NOT proxy directly to pods (must go through NGINX → Service → pods)

  **Recommended Agent Profile**:
  - **Category**: `writing`
    - Reason: Pure documentation task with embedded shell commands; no code generation or design decisions beyond following PDF allowance
  - **Skills**: []
    - Reason: Documentation does not require specialized code skills
  - **Skills Evaluated but Omitted**:
    - `terraform-style-guide`: Not needed — manual console steps, not Terraform
    - `playwright`: Not needed — screenshots taken manually by operator following runbook

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 8b (with T28, T29)
  - **Blocks**: T30 (evidence consolidation needs runbook + screenshots)
  - **Blocked By**: T13 (need NLB DNS), T22 (need Lambda authorizer ARN), T9 (need Cognito issuer URL for token testing), T26 (need pipeline to have deployed app)

  **References**:

  **Pattern References** (existing code to follow):
  - `docs/api-gateway-runbook.md` does not yet exist — create new from this template
  - `docs/evidence/` directory pattern → see T30 for index structure

  **API/Type References** (contracts to implement against):
  - `lambda-authorizer/index.js` (T22) — confirm payload v2.0 SIMPLE response shape `{ "isAuthorized": true|false, "context": {...} }`
  - Cognito token endpoint output: T9 generates `terraform output cognito_token_endpoint` and `cognito_resource_server_scope`

  **Test References** (testing patterns to follow):
  - T28 Postman collection — runbook curl examples must match Postman requests exactly

  **External References** (libraries and frameworks):
  - HTTP API + Lambda authorizer guide: `https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-lambda-authorizer.html` — payload v2.0 simple response section
  - HTTP API access logging: `https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-logging.html` — JSON `$context` variables
  - HTTP proxy integration: `https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-http.html`
  - Cognito M2M token request: `https://docs.aws.amazon.com/cognito/latest/developerguide/token-endpoint.html`

  **WHY Each Reference Matters**:
  - HTTP API guide: confirms simple response mode + cache TTL behavior — runbook must use SIMPLE not IAM mode
  - Access logging docs: required `$context.requestId`, `$context.authorizer.principalId`, `$context.integration.status` fields for evidence completeness
  - HTTP proxy integration: confirms `{proxy+}` greedy match path passing — runbook step 3 must use `{proxy+}` not `{proxy}`
  - Cognito M2M token: runbook step 9 token-fetch curl must include `client_credentials` grant + `weather-api/read` scope

  **Acceptance Criteria**:
  - [ ] `docs/api-gateway-runbook.md` exists, ≥10 numbered steps, all commands shell-copyable
  - [ ] Runbook includes troubleshooting section (≥3 error scenarios) and rollback section
  - [ ] All screenshots in `docs/evidence/05-app/api-gateway-screenshots/` exist (`ls docs/evidence/05-app/api-gateway-screenshots/*.png | wc -l` ≥ 10)
  - [ ] `docs/evidence/05-app/api-gateway-invoke-url.txt` exists with valid `https://*.execute-api.*.amazonaws.com/prod` URL
  - [ ] `markdownlint docs/api-gateway-runbook.md` → no errors
  - [ ] All NLB DNS / Lambda ARN / Cognito values in runbook are placeholders `<NLB_DNS>`, `<LAMBDA_ARN>`, `<COGNITO_DOMAIN>` (not hardcoded)
  - [ ] Runbook references `terraform output` commands for every variable (no manual lookup required)

  **QA Scenarios (MANDATORY)**:

  ```
  Scenario: Runbook executable end-to-end (happy path)
    Tool: Bash
    Preconditions: T13 NLB up, T22 Lambda deployed, T9 Cognito user pool ready, T26 app deployed to staging ns, runbook screenshots already captured
    Steps:
      1. Source env: source <(terraform -chdir=infra/envs/staging output -json | jq -r 'to_entries[] | "export \(.key | ascii_upcase)=\(.value.value)"')
      2. Get token: curl -s -X POST "$COGNITO_TOKEN_ENDPOINT" -H "Content-Type: application/x-www-form-urlencoded" -u "$COGNITO_CLIENT_ID:$COGNITO_CLIENT_SECRET" -d "grant_type=client_credentials&scope=weather-api/read" | jq -r .access_token > /tmp/token.txt
      3. Read invoke URL: INVOKE_URL=$(cat docs/evidence/05-app/api-gateway-invoke-url.txt)
      4. Call API: curl -sw "\nHTTP_CODE:%{http_code}\n" -H "Authorization: Bearer $(cat /tmp/token.txt)" "$INVOKE_URL/weather/forecast?lat=10.78&lon=106.70" | tee docs/evidence/05-app/api-gw-200-response.txt
      5. Assert: grep -q "HTTP_CODE:200" docs/evidence/05-app/api-gw-200-response.txt && grep -q "current_weather" docs/evidence/05-app/api-gw-200-response.txt
    Expected Result: HTTP 200, JSON contains `current_weather` and `temperature` fields from Open-Meteo
    Failure Indicators: HTTP_CODE:401 (token), HTTP_CODE:502 (NLB unreachable), HTTP_CODE:404 (route mismatch), missing `current_weather` (proxy not stripping prefix)
    Evidence: docs/evidence/05-app/api-gw-200-response.txt

  Scenario: Authorizer rejects request without token (negative)
    Tool: Bash
    Preconditions: API Gateway deployed with authorizer attached
    Steps:
      1. INVOKE_URL=$(cat docs/evidence/05-app/api-gateway-invoke-url.txt)
      2. curl -sw "\nHTTP_CODE:%{http_code}\n" "$INVOKE_URL/weather/forecast?lat=10.78&lon=106.70" | tee docs/evidence/05-app/api-gw-401-response.txt
      3. Assert: grep -q "HTTP_CODE:401" docs/evidence/05-app/api-gw-401-response.txt
    Expected Result: HTTP 401 from API Gateway (authorizer denies)
    Failure Indicators: HTTP 200 (authorizer not attached or misconfigured), HTTP 500 (Lambda crashed)
    Evidence: docs/evidence/05-app/api-gw-401-response.txt

  Scenario: Access logs reach CloudWatch (PDF mandate evidence)
    Tool: Bash
    Preconditions: Above happy-path call already executed
    Steps:
      1. sleep 30  # CloudWatch ingestion delay
      2. aws logs tail /aws/apigateway/max-weather-api --since 5m --format short | head -20 | tee docs/evidence/04-cloudwatch/api-gw-access-logs.txt
      3. Assert: grep -q '"status":200' docs/evidence/04-cloudwatch/api-gw-access-logs.txt
    Expected Result: At least one log entry with status 200, requestId, authorizer principalId
    Failure Indicators: Empty log group (access logging not enabled), missing fields (wrong JSON template)
    Evidence: docs/evidence/04-cloudwatch/api-gw-access-logs.txt
  ```

  **Evidence to Capture**:
  - [ ] `docs/api-gateway-runbook.md` (the runbook itself)
  - [ ] `docs/evidence/05-app/api-gateway-screenshots/step-{01..10}-*.png` (≥10 console screenshots)
  - [ ] `docs/evidence/05-app/api-gateway-invoke-url.txt` (invoke URL string)
  - [ ] `docs/evidence/05-app/api-gw-200-response.txt` (happy path response)
  - [ ] `docs/evidence/05-app/api-gw-401-response.txt` (no-token rejection)
  - [ ] `docs/evidence/04-cloudwatch/api-gw-access-logs.txt` (CloudWatch access log sample)

  **Commit**: YES (groups with T28, T29)
  - Message: `docs(api-gateway): manual setup runbook + evidence`
  - Files: `docs/api-gateway-runbook.md`, `docs/evidence/05-app/`, `docs/evidence/04-cloudwatch/api-gw-access-logs.txt`
  - Pre-commit: `markdownlint docs/api-gateway-runbook.md && test -s docs/evidence/05-app/api-gateway-invoke-url.txt`

- [x] 28. **Postman collection + Newman runner + token fetch script (D6 deliverable)**

  **What to do**:
  - Create `docs/postman/max-weather.postman_collection.json`:
    - Collection-level pre-request script: fetches OAuth2 token from Cognito using `client_credentials`, stores in `pm.collectionVariables.set("access_token", ...)` with 5-min TTL check (refresh if expired)
    - Collection-level Authorization: `Bearer {{access_token}}`
    - Folder `Weather`:
      - Request 1: `GET {{invoke_url}}/weather/health` → expects 200, body matches `{"status":"ok"}`
      - Request 2: `GET {{invoke_url}}/weather/forecast?lat=10.78&lon=106.70` (HCMC) → expects 200, body has `current_weather.temperature` (number)
      - Request 3: `GET {{invoke_url}}/weather/forecast?lat=21.03&lon=105.85` (Hanoi) → expects 200
      - Request 4: `GET {{invoke_url}}/weather/forecast?lat=invalid&lon=106.70` → expects 400 with error message
    - Folder `Auth Negative`:
      - Request 5: `GET {{invoke_url}}/weather/forecast` with empty Authorization header → expects 401
      - Request 6: `GET {{invoke_url}}/weather/forecast` with `Authorization: Bearer invalid.token.here` → expects 401
    - Each request has Tests tab with `pm.test()` assertions for status code and response shape
  - Create `docs/postman/max-weather.postman_environment.json`:
    - Variables: `cognito_domain`, `cognito_client_id`, `cognito_client_secret` (SECRET type), `cognito_scope=weather-api/read`, `invoke_url`, `access_token` (SECRET, populated by pre-request)
    - Default values use `{{}}` placeholders so user must populate before running
  - Create `scripts/get-token.sh`:
    - Sources `terraform output -json` from `infra/envs/staging`
    - POSTs to Cognito token endpoint with `client_credentials` grant
    - Prints token to stdout (no logging) — `set +x` enforced
    - Exit codes: 0 = success, 1 = curl error, 2 = no access_token in response
  - Create `scripts/run-postman.sh`:
    - Wrapper that: 1) generates fresh `tmp.postman_environment.json` from terraform outputs (so users don't manually edit), 2) runs `newman run docs/postman/max-weather.postman_collection.json -e tmp.postman_environment.json --reporters cli,htmlextra --reporter-htmlextra-export docs/evidence/05-app/postman-report.html`, 3) deletes `tmp.postman_environment.json`
  - Add `package.json` (root or `tools/`) with `newman` + `newman-reporter-htmlextra` devDependencies for reproducibility (or document `npm install -g`)
  - Document in README how to run: `make postman` shortcut

  **Must NOT do**:
  - Do NOT commit real Cognito client_secret or access_token in the collection/environment JSON — only `{{}}` placeholders
  - Do NOT use Postman Cloud sync (offline file only)
  - Do NOT use legacy v2.0 collection format — must be v2.1.0
  - Do NOT include any URLs with hardcoded account ID or region — use environment variables
  - Do NOT skip negative test cases (PDF expects "API authorization is mandatory" — must demonstrate authorizer rejects bad tokens)
  - Do NOT depend on Postman desktop app for CI — Newman CLI must work standalone
  - Do NOT log tokens or secrets in `scripts/get-token.sh` (no `set -x`, no `echo $TOKEN`)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Cross-domain task (JSON schema crafting + bash scripting + auth flow understanding); not pure code, not pure docs
  - **Skills**: []
    - Reason: Postman collection schema and Newman are well-documented; no installed skill specializes in API testing tooling
  - **Skills Evaluated but Omitted**:
    - `playwright`: Wrong domain — Postman/Newman is HTTP testing, not browser automation
    - `backend-code-review`: Reviews backend `.py` only, not JSON collections

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 8b (with T27, T29)
  - **Blocks**: T30 (evidence index references postman-report.html)
  - **Blocked By**: T9 (Cognito client + scope), T22 (authorizer behavior), T27 (invoke URL must exist)

  **References**:

  **Pattern References** (existing code to follow):
  - `docs/postman/` directory does not yet exist — create new
  - `scripts/get-token.sh` — follow shell style of `scripts/teardown.sh` (T32) for consistency: `set -euo pipefail`, function-based, `trap` cleanup

  **API/Type References** (contracts to implement against):
  - Weather API contract from T20: `GET /health` returns `{"status":"ok"}`; `GET /forecast?lat=&lon=` proxies to Open-Meteo
  - Cognito token endpoint shape: `{"access_token":"...", "expires_in":3600, "token_type":"Bearer"}`
  - Lambda authorizer payload v2.0 simple response (T22): rejects produce HTTP 401 from API Gateway

  **Test References** (testing patterns to follow):
  - T20 supertest tests — Postman tests should mirror the same assertions for parity

  **External References** (libraries and frameworks):
  - Postman Collection Format v2.1: `https://schema.postman.com/collection/json/v2.1.0/draft-07/collection.json`
  - Newman CLI: `https://learning.postman.com/docs/collections/using-newman-cli/command-line-integration-with-newman/`
  - newman-reporter-htmlextra: `https://github.com/DannyDainton/newman-reporter-htmlextra`
  - Postman pre-request scripting: `https://learning.postman.com/docs/writing-scripts/pre-request-scripts/`
  - Cognito M2M curl: `https://docs.aws.amazon.com/cognito/latest/developerguide/token-endpoint.html#token-endpoint-clients`

  **WHY Each Reference Matters**:
  - Schema URL: collection MUST validate against v2.1.0 schema for newman compatibility — wrong schema breaks `newman run`
  - htmlextra reporter: required for HTML evidence file in `docs/evidence/05-app/postman-report.html` — default reporters produce only CLI output
  - Pre-request scripting: collection MUST refresh token automatically; users won't manually paste tokens for 6 requests
  - Cognito curl docs: confirms `Authorization: Basic base64(client_id:client_secret)` Basic auth header format for confidential client

  **Acceptance Criteria**:
  - [ ] `docs/postman/max-weather.postman_collection.json` validates against schema (run `ajv validate -s collection-schema.json -d collection.json` or `newman run --dry-run`)
  - [ ] Collection contains exactly 6 requests across 2 folders (4 happy + 2 negative)
  - [ ] Each request has ≥1 `pm.test()` assertion in Tests tab
  - [ ] `docs/postman/max-weather.postman_environment.json` exists with all secrets as empty placeholders
  - [ ] `scripts/get-token.sh` is executable (`chmod +x`), has shebang, has `set -euo pipefail`
  - [ ] `bash -n scripts/get-token.sh` and `bash -n scripts/run-postman.sh` → no syntax errors
  - [ ] `shellcheck scripts/*.sh` → no warnings (or documented exceptions)
  - [ ] `gitleaks detect --source docs/postman` → no secrets leaked
  - [ ] `make postman` target runs newman successfully against deployed staging stack

  **QA Scenarios (MANDATORY)**:

  ```
  Scenario: Newman runs full collection successfully (happy path)
    Tool: Bash
    Preconditions: T27 API Gateway deployed, staging app running, Cognito client active, terraform outputs present
    Steps:
      1. cd /home/ubuntu/Workspace/assessment
      2. bash scripts/run-postman.sh 2>&1 | tee docs/evidence/05-app/newman-output.txt
      3. Assert exit code: echo $? == 0
      4. Assert all assertions passed: grep -E "[0-9]+ assertions.*[0-9]+ failed" docs/evidence/05-app/newman-output.txt | grep -q "0 failed"
      5. Assert HTML report generated: test -s docs/evidence/05-app/postman-report.html
      6. Assert no secrets in output: ! grep -E "(eyJ[a-zA-Z0-9_-]{20,}|client_secret)" docs/evidence/05-app/newman-output.txt
    Expected Result: All 6 requests pass, 12+ assertions pass, HTML report ≥ 50 KB, no token/secret leaked in stdout
    Failure Indicators: "0 requests" (env not loaded), "ECONNREFUSED" (NLB down), "401" on happy-path requests (token not refreshed in pre-request)
    Evidence: docs/evidence/05-app/newman-output.txt, docs/evidence/05-app/postman-report.html

  Scenario: Token script fails gracefully on bad credentials (negative)
    Tool: Bash
    Preconditions: scripts/get-token.sh exists
    Steps:
      1. COGNITO_CLIENT_SECRET=wrong-secret-xyz bash scripts/get-token.sh 2>&1 | tee /tmp/token-err.txt
      2. Assert exit code: test $? -ne 0
      3. Assert no token leaked: ! grep -E "eyJ[a-zA-Z0-9_-]{20,}" /tmp/token-err.txt
      4. Assert error message: grep -qi "invalid_client\|unauthorized" /tmp/token-err.txt
    Expected Result: Non-zero exit, error message about invalid_client, NO partial tokens in output
    Failure Indicators: Exit 0 (script swallows error), "eyJ..." in stderr (token leaked), no error message (silent failure)
    Evidence: /tmp/token-err.txt (do not commit)

  Scenario: Collection rejects unauthorized request (built-in negative test)
    Tool: Bash
    Preconditions: Collection has "Auth Negative" folder
    Steps:
      1. newman run docs/postman/max-weather.postman_collection.json -e tmp.postman_environment.json --folder "Auth Negative" 2>&1 | tee /tmp/newman-neg.txt
      2. Assert: grep -q "0 failed" /tmp/newman-neg.txt  (negative tests pass = received expected 401)
      3. Assert: grep -q "expected response code to be 401" /tmp/newman-neg.txt
    Expected Result: 2 requests run, 0 assertions fail (because 401 IS the expected outcome)
    Failure Indicators: "expected 401 but got 200" (authorizer not enforcing), newman crashes
    Evidence: docs/evidence/05-app/newman-negative-tests.txt
  ```

  **Evidence to Capture**:
  - [ ] `docs/postman/max-weather.postman_collection.json` (the deliverable D6)
  - [ ] `docs/postman/max-weather.postman_environment.json` (template with placeholders)
  - [ ] `scripts/get-token.sh`, `scripts/run-postman.sh`
  - [ ] `docs/evidence/05-app/newman-output.txt` (last successful run output)
  - [ ] `docs/evidence/05-app/postman-report.html` (htmlextra report)
  - [ ] `docs/evidence/05-app/newman-negative-tests.txt` (auth rejection proof)

  **Commit**: YES (groups with T27, T29)
  - Message: `feat(postman): D6 collection + newman runner + token script`
  - Files: `docs/postman/`, `scripts/get-token.sh`, `scripts/run-postman.sh`, `Makefile` (add `postman` target)
  - Pre-commit: `bash -n scripts/*.sh && shellcheck scripts/*.sh && gitleaks detect --source docs/postman --no-banner && newman run docs/postman/max-weather.postman_collection.json --dry-run`

- [x] 29. **Load test (k6) + HPA scaling evidence + CloudWatch logs evidence (PDF mandate)**

  **What to do**:
  - Create `tests/load/weather-load.js` (k6 script):
    - Stages: 30s ramp 0→10 VU, 60s sustain 10 VU, 60s ramp 10→50 VU, 120s sustain 50 VU, 30s ramp-down → 0 VU
    - Pre-test setup: fetch token via Cognito (k6 `setup()` function), reuse across iterations
    - Test scenario: alternates `GET /weather/forecast?lat=10.78&lon=106.70` (HCMC) and `GET /weather/forecast?lat=21.03&lon=105.85` (Hanoi)
    - Thresholds: `http_req_duration p(95)<2000ms`, `http_req_failed rate<0.05`, `checks rate>0.95`
    - Output: `--summary-export=docs/evidence/08-loadtest/k6-summary.json`, JSON metrics streamed to `docs/evidence/08-loadtest/k6-metrics.json`
  - Create `scripts/run-loadtest.sh`:
    - Records HPA state BEFORE: `kubectl get hpa -n weather-staging -o yaml > docs/evidence/08-loadtest/hpa-before.yaml`
    - Records pod count BEFORE: `kubectl get pods -n weather-staging -l app=weather-api --no-headers | wc -l > docs/evidence/08-loadtest/pods-before.txt`
    - Starts background watcher: `kubectl get hpa -n weather-staging -w --no-headers > docs/evidence/08-loadtest/hpa-watch.log &` (PID saved for kill)
    - Starts background pod watcher: `kubectl get pods -n weather-staging -l app=weather-api -w --no-headers > docs/evidence/08-loadtest/pods-watch.log &`
    - Runs k6: `k6 run tests/load/weather-load.js`
    - After test: sleeps 60s for HPA stabilization, captures HPA AFTER, pod count AFTER
    - Kills watchers, captures `kubectl describe hpa weather-api -n weather-staging > docs/evidence/08-loadtest/hpa-describe.txt`
    - Captures `kubectl top pods -n weather-staging > docs/evidence/08-loadtest/pods-top.txt`
  - Capture CloudWatch logs evidence (PDF mandate "CloudWatch services and scaling should be tested"):
    - `aws logs tail /aws/eks/max-weather/application --since 10m --format short > docs/evidence/04-cloudwatch/eks-app-logs.txt` (Fluent Bit shipped logs from T15)
    - `aws logs tail /aws/eks/max-weather/cluster --since 10m --format short > docs/evidence/04-cloudwatch/eks-control-plane-logs.txt`
    - `aws logs tail /aws/lambda/max-weather-authorizer --since 10m --format short > docs/evidence/04-cloudwatch/lambda-authorizer-logs.txt`
    - `aws cloudwatch get-metric-statistics --namespace AWS/EKS --metric-name node_cpu_utilization --start-time $(date -u -d '15 min ago' +%FT%TZ) --end-time $(date -u +%FT%TZ) --period 60 --statistics Average > docs/evidence/04-cloudwatch/eks-cpu-metric.json` (or use Container Insights metric if enabled)
  - Add `Makefile` target `load-test` invoking `scripts/run-loadtest.sh`
  - Document in `docs/evidence/08-loadtest/README.md`: how to interpret results, expected scaling pattern (pods grow from 2 → 5+ during sustain phase if CPU target hit)

  **Must NOT do**:
  - Do NOT run load test against `prod` namespace — staging only
  - Do NOT exceed 50 concurrent VUs (cost control + Open-Meteo respects fair-use)
  - Do NOT skip the BEFORE/AFTER HPA snapshots — required to PROVE scaling occurred
  - Do NOT use `hey` or `ab` — k6 chosen for thresholds + JSON reports
  - Do NOT commit `k6-metrics.json` if > 5 MB (gitignore large files, keep summary only)
  - Do NOT skip the kubectl `-w` watchers (need timestamped scaling events as evidence)
  - Do NOT use API Gateway invoke URL during load test (API Gateway throttling at burst=100; bypass via NLB DNS for cleaner pod-level scaling signal — DOCUMENT this choice)
  - Do NOT cache token for entire test if it expires — k6 setup() runs once but our 5-min test fits within token TTL

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Multi-domain orchestration (k6 scripting + kubectl observability + CloudWatch CLI + bash glue); no specialized skill covers this combination
  - **Skills**: []
    - Reason: No installed skill specializes in k6 or HPA verification
  - **Skills Evaluated but Omitted**:
    - `playwright`: Wrong domain — load testing is HTTP, not browser
    - `terraform-style-guide`: No Terraform code in this task
    - `backend-code-review`: Reviews Python only

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 8b (with T27, T28)
  - **Blocks**: T30 (evidence index needs load test artifacts)
  - **Blocked By**: T18 (metrics-server for HPA), T15 (Fluent Bit for log evidence), T26 (app deployed via Jenkins), T27 (NLB DNS for direct call)

  **References**:

  **Pattern References** (existing code to follow):
  - `tests/load/` does not yet exist — create new
  - `scripts/run-loadtest.sh` follows same shell style as `scripts/get-token.sh` (T28): `set -euo pipefail`, `trap` cleanup for background PIDs

  **API/Type References** (contracts to implement against):
  - HPA from T23: target CPU 70%, min 2 max 10 replicas (staging) — load test must push CPU > 70% to trigger scale-up
  - Service from T23: `weather-api.weather-staging.svc.cluster.local` — but k6 calls via NLB DNS for external load
  - Open-Meteo URL from T20: `https://api.open-meteo.com/v1/forecast`

  **Test References** (testing patterns to follow):
  - T28 token fetch in pre-request — k6 setup() mirrors that flow

  **External References** (libraries and frameworks):
  - k6 Stages: `https://grafana.com/docs/k6/latest/using-k6/k6-options/reference/#stages`
  - k6 Thresholds: `https://grafana.com/docs/k6/latest/using-k6/thresholds/`
  - k6 setup() / teardown(): `https://grafana.com/docs/k6/latest/using-k6/test-lifecycle/`
  - HPA algorithm: `https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#algorithm-details`
  - kubectl watch: `https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-get-em-` (`-w` flag)
  - CloudWatch Logs tail: `https://docs.aws.amazon.com/cli/latest/reference/logs/tail.html`
  - aws-for-fluent-bit log group convention: T15 ships to `/aws/eks/<cluster>/application`

  **WHY Each Reference Matters**:
  - k6 stages: load profile must include ramp-up so HPA has time to react (sudden spikes don't always trigger HPA due to cooldown)
  - HPA algorithm: `desiredReplicas = ceil(currentReplicas * (currentMetricValue / desiredMetricValue))` — confirms why 50 VU should push 2 pods → 4-5 pods
  - kubectl `-w`: watch mode produces timestamped events showing scaling decisions in real time — without this, we have only before/after snapshots
  - CloudWatch tail: `--since 10m` window aligns with load test duration so logs evidence is contemporaneous

  **Acceptance Criteria**:
  - [ ] `tests/load/weather-load.js` exists, validates with `k6 inspect tests/load/weather-load.js`
  - [ ] Load test completes without script errors (exit 0)
  - [ ] `docs/evidence/08-loadtest/k6-summary.json` exists, `http_req_failed` rate < 0.05
  - [ ] `docs/evidence/08-loadtest/hpa-before.yaml` shows replicas ≤ 2; `docs/evidence/08-loadtest/hpa-describe.txt` shows replicas ≥ 3 OR documented why CPU never crossed threshold (e.g., "Open-Meteo cached responses kept CPU low — load test demonstrates HPA wiring; force scale via `kubectl scale --replicas=5` to prove scale-up path works")
  - [ ] `docs/evidence/08-loadtest/hpa-watch.log` contains ≥ 1 line with replica count change
  - [ ] `docs/evidence/04-cloudwatch/eks-app-logs.txt` contains application log lines from `weather-api` pods (proves Fluent Bit shipping)
  - [ ] `docs/evidence/04-cloudwatch/lambda-authorizer-logs.txt` contains Lambda invocation logs (if any auth requests during window)
  - [ ] `docs/evidence/08-loadtest/README.md` exists, documents test methodology + interpretation

  **QA Scenarios (MANDATORY)**:

  ```
  Scenario: Load test executes and HPA reacts (happy path)
    Tool: Bash
    Preconditions: Staging app deployed, HPA active (kubectl get hpa shows target CPU%), NLB DNS reachable
    Steps:
      1. cd /home/ubuntu/Workspace/assessment
      2. mkdir -p docs/evidence/08-loadtest docs/evidence/04-cloudwatch
      3. bash scripts/run-loadtest.sh 2>&1 | tee docs/evidence/08-loadtest/run.log
      4. Assert exit 0: test ${PIPESTATUS[0]} -eq 0
      5. Assert summary exists: test -s docs/evidence/08-loadtest/k6-summary.json
      6. Assert request count: jq '.metrics.http_reqs.values.count' docs/evidence/08-loadtest/k6-summary.json | awk '{exit !($1 > 100)}'
      7. Assert error rate: jq '.metrics.http_req_failed.values.rate' docs/evidence/08-loadtest/k6-summary.json | awk '{exit !($1 < 0.05)}'
      8. Assert HPA snapshots: test -s docs/evidence/08-loadtest/hpa-before.yaml && test -s docs/evidence/08-loadtest/hpa-describe.txt
    Expected Result: ≥100 requests, error rate <5%, HPA before/after files captured, scaling activity in watch.log
    Failure Indicators: k6 binary missing, NLB ECONNREFUSED, all requests 401 (token expired), no HPA file (kubectl context wrong)
    Evidence: docs/evidence/08-loadtest/run.log + all k6 + kubectl artifacts

  Scenario: HPA scale-up happened OR documented fallback (PDF scaling mandate)
    Tool: Bash
    Preconditions: Load test completed
    Steps:
      1. BEFORE_REPLICAS=$(grep -E "^\s+replicas:" docs/evidence/08-loadtest/hpa-before.yaml | head -1 | awk '{print $2}')
      2. AFTER_REPLICAS=$(grep "Current replicas" docs/evidence/08-loadtest/hpa-describe.txt | awk '{print $3}')
      3. If [ "$AFTER_REPLICAS" -gt "$BEFORE_REPLICAS" ]; then echo "PASS: scaled $BEFORE_REPLICAS → $AFTER_REPLICAS" > docs/evidence/08-loadtest/scaling-verdict.txt
      4. Else: bash scripts/force-scale-demo.sh  (manual replica bump as fallback proof, documented in README)
      5. Capture final: kubectl get pods -n weather-staging -l app=weather-api --no-headers | wc -l > docs/evidence/08-loadtest/pods-after.txt
      6. Assert evidence file exists: test -s docs/evidence/08-loadtest/scaling-verdict.txt
    Expected Result: Either organic scale-up logged, OR fallback `kubectl scale` demonstrates HPA->RS->Pod path works
    Failure Indicators: Both organic and forced scaling fail (RBAC/quotas/PDB blocking)
    Evidence: docs/evidence/08-loadtest/scaling-verdict.txt, docs/evidence/08-loadtest/pods-after.txt

  Scenario: CloudWatch evidence captured for PDF mandate (negative case = no logs = FAIL)
    Tool: Bash
    Preconditions: Fluent Bit + EKS control-plane logging enabled (T15, T10), Lambda invoked recently
    Steps:
      1. test -s docs/evidence/04-cloudwatch/eks-app-logs.txt
      2. grep -q "weather-api" docs/evidence/04-cloudwatch/eks-app-logs.txt
      3. test -s docs/evidence/04-cloudwatch/eks-control-plane-logs.txt
      4. test -s docs/evidence/04-cloudwatch/lambda-authorizer-logs.txt
      5. test -s docs/evidence/04-cloudwatch/eks-cpu-metric.json
      6. jq '.Datapoints | length' docs/evidence/04-cloudwatch/eks-cpu-metric.json | awk '{exit !($1 > 0)}'
    Expected Result: All 4 evidence files non-empty, app logs reference weather-api, CPU metric has data points
    Failure Indicators: Empty files (Fluent Bit IRSA broken / log group missing / Container Insights not enabled)
    Evidence: docs/evidence/04-cloudwatch/* (all four files)
  ```

  **Evidence to Capture**:
  - [ ] `tests/load/weather-load.js`, `scripts/run-loadtest.sh`, `scripts/force-scale-demo.sh` (fallback)
  - [ ] `docs/evidence/08-loadtest/k6-summary.json`, `k6-metrics.json` (≤5MB), `run.log`
  - [ ] `docs/evidence/08-loadtest/hpa-before.yaml`, `hpa-describe.txt`, `hpa-watch.log`
  - [ ] `docs/evidence/08-loadtest/pods-before.txt`, `pods-after.txt`, `pods-watch.log`, `pods-top.txt`
  - [ ] `docs/evidence/08-loadtest/scaling-verdict.txt`, `README.md`
  - [ ] `docs/evidence/04-cloudwatch/eks-app-logs.txt`, `eks-control-plane-logs.txt`, `lambda-authorizer-logs.txt`, `eks-cpu-metric.json`

  **Commit**: YES (groups with T27, T28)
  - Message: `test(load): k6 load test + HPA + CloudWatch evidence (PDF mandate)`
  - Files: `tests/load/`, `scripts/run-loadtest.sh`, `scripts/force-scale-demo.sh`, `docs/evidence/08-loadtest/`, `docs/evidence/04-cloudwatch/`, `Makefile` (add `load-test` target), `.gitignore` (exclude `*.json` > 5MB)
  - Pre-commit: `k6 inspect tests/load/weather-load.js && bash -n scripts/run-loadtest.sh && shellcheck scripts/*.sh`

- [x] 30. **Evidence consolidation: docs/evidence/ index + verification script**

  **What to do**:
  - Create `docs/evidence/README.md`: top-level index linking every evidence subdirectory with brief description, target audience (assessor), how to verify each artifact
    - Section per directory: `01-terraform/` (terraform plan/apply outputs, state list), `02-eks/` (kubectl get nodes/pods, helm list), `03-k8s/` (kubectl describe deployments + ingress + hpa), `04-cloudwatch/` (log samples + metrics from T29), `05-app/` (API Gateway runbook outputs + Postman + curl outputs), `06-lambda/` (authorizer test invocations + CloudWatch logs), `07-jenkins/` (pipeline run screenshots + console logs), `08-loadtest/` (k6 + HPA from T29)
  - Capture additional evidence not covered by other tasks:
    - `01-terraform/`: `terraform -chdir=infra/envs/staging plan -no-color > plan.txt` (last clean plan), `terraform state list > state-list.txt`, `terraform output -json > outputs.json` (sanitized — no secrets), `terraform fmt -check -recursive > fmt-check.txt` (must be empty), `terraform validate > validate.txt`
    - `02-eks/`: `kubectl get nodes -o wide > nodes.txt`, `kubectl get pods -A > pods-all-ns.txt`, `helm list -A > helm-releases.txt`, `kubectl get crds | grep -E "(externalsecrets|ingress|targetgroupbindings)" > crds.txt`, `aws eks describe-cluster --name max-weather > cluster.json` (sanitized)
    - `03-k8s/`: `kubectl describe deploy weather-api -n weather-staging > deploy-describe.txt`, `kubectl describe svc weather-api -n weather-staging > svc-describe.txt`, `kubectl describe ingress weather-api -n weather-staging > ingress-describe.txt`, `kubectl get networkpolicy -A > netpol.txt`, `kubectl get resourcequota -A > resourcequota.txt`
    - `06-lambda/`: `aws lambda invoke --function-name max-weather-authorizer --payload file://docs/evidence/06-lambda/test-event-allow.json /tmp/out.json && cp /tmp/out.json docs/evidence/06-lambda/invoke-allow-response.json`, same for deny event, `aws lambda get-function-configuration --function-name max-weather-authorizer > config.json`
    - `07-jenkins/`: pipeline screenshot from console (manual capture: build summary, stage view, blue ocean), `wget http://<jenkins>/job/max-weather-staging/lastBuild/consoleText -O console.txt` (or operator copies), Jenkinsfile snapshot copy
  - Create `scripts/verify-evidence.sh`:
    - Iterates expected file list (hardcoded array): for each path, asserts `test -s` (non-empty)
    - Outputs colored PASS/FAIL summary
    - Exit 0 only if all evidence present
    - Used by F1 reviewer to confirm completeness
  - Create `scripts/sanitize-outputs.sh`:
    - Strips `client_secret`, `access_key`, account_id, NLB IPs from terraform-output JSON before commit (jq filter)
    - Used by `01-terraform/outputs.json` capture
  - Add `make evidence` target: re-runs all evidence capture commands non-destructively
  - Add `make verify-evidence` target: runs `scripts/verify-evidence.sh`

  **Must NOT do**:
  - Do NOT commit raw `terraform output -json` without sanitization (leaks Cognito client_secret)
  - Do NOT commit Jenkins console logs containing AWS access keys (Jenkins masks them, but verify with gitleaks)
  - Do NOT commit CloudWatch log samples containing user-specific tokens (Lambda authorizer might log token hashes)
  - Do NOT include screenshots showing AWS account ID in URL bar (blur with operator action OR exclude)
  - Do NOT commit files larger than 5 MB (k6-metrics.json edge case from T29)
  - Do NOT generate evidence in CI — must be hand-captured after manual operator verification (auditor-grade)
  - Do NOT delete evidence between runs — append-only directory

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Cross-cutting orchestration (terraform CLI + kubectl + aws CLI + jq + bash + markdown); requires breadth across all prior tasks
  - **Skills**: []
    - Reason: No specialized skill aggregates evidence
  - **Skills Evaluated but Omitted**:
    - `terraform-style-guide`: Reviews HCL style; this task captures Terraform OUTPUT, not authors HCL
    - `backend-code-review`: Wrong domain

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 9 (sequential, after T27/T28/T29 complete)
  - **Blocks**: T31 README references evidence index, F1 audit reads evidence
  - **Blocked By**: T1–T29 (everything must be deployed and stable for evidence to be authentic)

  **References**:

  **Pattern References** (existing code to follow):
  - `docs/evidence/` directory created incrementally by T1 (`.gitkeep`), T27, T28, T29; this task adds top-level README + verification
  - `scripts/verify-evidence.sh` follows same shell style as `scripts/teardown.sh` (T32)

  **API/Type References** (contracts to implement against):
  - All `terraform output` names defined in T3-T26 modules (cluster_name, nlb_dns, cognito_*, etc.) — sanitize script must match those names
  - `aws lambda invoke` payload format: API Gateway authorizer payload v2.0 from T22

  **Test References** (testing patterns to follow):
  - F1 audit (later) uses `verify-evidence.sh` as part of compliance check — script API stable

  **External References** (libraries and frameworks):
  - jq filter for redaction: `https://jqlang.github.io/jq/manual/#walk(f)` — `walk` recursively redacts matching keys
  - terraform output -json: `https://developer.hashicorp.com/terraform/cli/commands/output#json`
  - aws lambda invoke: `https://docs.aws.amazon.com/cli/latest/reference/lambda/invoke.html`
  - gitleaks scan: `https://github.com/gitleaks/gitleaks#scanning`

  **WHY Each Reference Matters**:
  - jq walk: handles nested JSON sanitization (account_ids/secrets in deep terraform output structures); naive `sed` misses nested keys
  - terraform output --json: only `--json` mode preserves types for sanitize script; default text format breaks redaction
  - lambda invoke: payload format must match what API Gateway sends in production, otherwise authorizer testing is invalid
  - gitleaks: CI gate prevents committing secrets even if sanitize script has bugs (defense in depth)

  **Acceptance Criteria**:
  - [ ] `docs/evidence/README.md` exists, has section per subdirectory, ≥1 link per artifact
  - [ ] `scripts/verify-evidence.sh` is executable, has shebang, `set -euo pipefail`
  - [ ] `bash scripts/verify-evidence.sh` exits 0 → all expected evidence files present and non-empty
  - [ ] `gitleaks detect --source docs/evidence` → no findings
  - [ ] All evidence files ≤ 5 MB (`find docs/evidence -size +5M | wc -l` == 0)
  - [ ] `docs/evidence/01-terraform/fmt-check.txt` is empty (Terraform formatted)
  - [ ] `markdownlint docs/evidence/README.md` → no errors
  - [ ] `make verify-evidence` target works
  - [ ] No screenshots contain account ID or secrets (visual spot check by operator, documented in README)

  **QA Scenarios (MANDATORY)**:

  ```
  Scenario: Verification script confirms all evidence present (happy path)
    Tool: Bash
    Preconditions: T1–T29 complete, evidence captured
    Steps:
      1. cd /home/ubuntu/Workspace/assessment
      2. bash scripts/verify-evidence.sh 2>&1 | tee /tmp/verify.txt
      3. Assert exit 0: test ${PIPESTATUS[0]} -eq 0
      4. Assert PASS messages: grep -c "PASS" /tmp/verify.txt | awk '{exit !($1 >= 30)}'
      5. Assert no FAIL messages: ! grep -q "FAIL" /tmp/verify.txt
    Expected Result: Script exits 0, ≥30 PASS lines (one per evidence file), zero FAILs
    Failure Indicators: Missing evidence files (grep "FAIL" finds them with paths), exit non-zero
    Evidence: /tmp/verify.txt → keep as docs/evidence/00-verify-summary.txt

  Scenario: Sanitization removes secrets before commit (security)
    Tool: Bash
    Preconditions: docs/evidence/01-terraform/outputs.json exists
    Steps:
      1. ! grep -E "(client_secret|AKIA[0-9A-Z]{16}|aws_secret_access_key)" docs/evidence/01-terraform/outputs.json
      2. ! grep -E "[0-9]{12}" docs/evidence/01-terraform/outputs.json  (no 12-digit account IDs)
      3. gitleaks detect --source docs/evidence --no-banner --report-path /tmp/gitleaks.json
      4. Assert: jq '.[]?' /tmp/gitleaks.json | wc -l → 0
    Expected Result: No secrets, no account IDs, gitleaks finds 0 leaks across docs/evidence/
    Failure Indicators: grep finds AKIA prefix (key leaked), 12-digit number (account ID), gitleaks JSON has entries
    Evidence: gitleaks scan report → docs/evidence/01-terraform/gitleaks-report.json (must be empty array)

  Scenario: Lambda authorizer test invocations work (negative + positive)
    Tool: Bash
    Preconditions: T22 Lambda deployed, test event JSONs prepared
    Steps:
      1. aws lambda invoke --function-name max-weather-authorizer --payload file://docs/evidence/06-lambda/test-event-allow.json --cli-binary-format raw-in-base64-out /tmp/allow.json > /tmp/allow-meta.json
      2. jq -e '.isAuthorized == true' /tmp/allow.json
      3. aws lambda invoke --function-name max-weather-authorizer --payload file://docs/evidence/06-lambda/test-event-deny.json --cli-binary-format raw-in-base64-out /tmp/deny.json > /tmp/deny-meta.json
      4. jq -e '.isAuthorized == false' /tmp/deny.json
      5. cp /tmp/allow.json docs/evidence/06-lambda/invoke-allow-response.json
      6. cp /tmp/deny.json docs/evidence/06-lambda/invoke-deny-response.json
    Expected Result: Allow event returns isAuthorized:true; deny event returns isAuthorized:false
    Failure Indicators: Lambda errors (FunctionError in meta), wrong isAuthorized value (authorizer logic broken)
    Evidence: docs/evidence/06-lambda/invoke-{allow,deny}-response.json
  ```

  **Evidence to Capture**:
  - [ ] `docs/evidence/README.md` (the index)
  - [ ] `scripts/verify-evidence.sh`, `scripts/sanitize-outputs.sh`
  - [ ] `docs/evidence/01-terraform/{plan.txt,state-list.txt,outputs.json,fmt-check.txt,validate.txt,gitleaks-report.json}`
  - [ ] `docs/evidence/02-eks/{nodes.txt,pods-all-ns.txt,helm-releases.txt,crds.txt,cluster.json}`
  - [ ] `docs/evidence/03-k8s/{deploy-describe.txt,svc-describe.txt,ingress-describe.txt,netpol.txt,resourcequota.txt}`
  - [ ] `docs/evidence/06-lambda/{invoke-allow-response.json,invoke-deny-response.json,config.json,test-event-allow.json,test-event-deny.json}`
  - [ ] `docs/evidence/07-jenkins/{console.txt,pipeline-screenshots/*.png,Jenkinsfile.snapshot}`
  - [ ] `docs/evidence/00-verify-summary.txt` (output of verify-evidence.sh)

  **Commit**: YES (separate, atomic evidence commit)
  - Message: `docs(evidence): consolidate evidence index + verification script`
  - Files: `docs/evidence/`, `scripts/verify-evidence.sh`, `scripts/sanitize-outputs.sh`, `Makefile` (add `evidence` and `verify-evidence` targets)
  - Pre-commit: `bash scripts/verify-evidence.sh && gitleaks detect --source docs/evidence --no-banner && find docs/evidence -size +5M | wc -l | grep -q "^0$"`

- [x] 31. **Top-level README.md: architecture, prerequisites, run, teardown, troubleshooting**

  **What to do**:
  - Create `/README.md` (project root) with sections in this order:
    1. **Title + Badges**: `# Max Weather — 101 Digital DevOps Assessment` + (optional) build status placeholder
    2. **TL;DR**: 3 sentences (what + how + key tech stack)
    3. **Architecture Diagram**: embed `docs/architecture.png` (`![Architecture](docs/architecture.png)`) with link to `.drawio` source
    4. **Deliverables Checklist (D1–D6)**: table mapping PDF deliverable → repo path → evidence link
       - D1 Architecture diagram → `docs/architecture.{drawio,png}`
       - D2 Terraform infra → `infra/`
       - D3 Kubernetes manifests → `k8s/`
       - D4 Jenkinsfile → `Jenkinsfile`
       - D5 Hosted API on API Gateway → `docs/api-gateway-runbook.md` + invoke URL in evidence
       - D6 Postman collection → `docs/postman/max-weather.postman_collection.json`
    5. **Prerequisites**: AWS account, region us-east-1, IAM user with admin (assessment scope), tools (terraform 1.9+, kubectl 1.30, helm 3.15+, awscli 2.x, jq, k6, newman, gitleaks)
    6. **Quick Start**: numbered commands
       - `make bootstrap` (T3 S3+DynamoDB)
       - `cd infra/envs/staging && terraform init && terraform apply -auto-approve` (Phase 1: networking + IAM)
       - `terraform apply -target=module.eks_irsa -auto-approve` (Phase 2 if needed)
       - `aws eks update-kubeconfig --name max-weather --region us-east-1`
       - `make deploy-helm` (T13-T18 Helm releases)
       - `make build-push` (T24 ECR images + Lambda ZIP)
       - `make deploy-app` (T23 kustomize apply via Jenkins)
       - `make deploy-api-gw` (manual — opens runbook)
       - `make postman` (T28 newman validation)
       - `make load-test` (T29 k6 + HPA evidence)
       - `make evidence && make verify-evidence` (T30)
       - `make teardown` (T32)
    7. **Repository Layout**: tree of top-level dirs with one-line descriptions (use the planned layout from context)
    8. **Configuration**: list of `terraform.tfvars` variables (region, cluster_name, vpc_cidr, node_instance_type, node_min/max, jenkins_admin_ip), defaults, override pattern (env vars vs `-var-file`)
    9. **Cost Estimate**: simple table (EKS control plane $73/mo, 2× t3.medium $60/mo, NAT gateway $33/mo, NLB $16/mo, Jenkins t3.medium $30/mo, total ~$215/mo prorated to ~$15 for 2-day demo) + reminder to teardown
    10. **Authentication**: how to fetch token (`scripts/get-token.sh`), how to use with curl/Postman, scope `weather-api/read`
    11. **Observability**: where logs live (CloudWatch group names), how to tail (`aws logs tail`), how to view HPA (`kubectl get hpa -w`)
    12. **Troubleshooting**: ≥6 entries (NLB not reachable / EKS auth denied / Lambda 502 / HPA stuck / image pull backoff / Jenkins build failure / token expired)
    13. **Teardown**: warning + `make teardown` + manual API Gateway delete + cloud-nuke as last resort
    14. **Security Notes**: secrets via External Secrets only, no hardcoded keys, gitleaks pre-commit, IAM least-privilege boundaries
    15. **Out of Scope (Explicit)**: prod environment promotion automation, custom domain + TLS, multi-region, Karpenter, service mesh, Datadog/Prometheus/Grafana
    16. **License + Attribution**: assessment context, contact (placeholder)
  - Inline shell snippets MUST be copy-pasteable (no `<placeholder>` without explanation)
  - Add `make help` target listing all Makefile targets with one-line descriptions; document in README
  - Cross-link to `docs/api-gateway-runbook.md`, `docs/evidence/README.md`, `infra/envs/staging/README.md` (per-env), `k8s/README.md`

  **Must NOT do**:
  - Do NOT include any Vietnamese in this file (English-only repo)
  - Do NOT include AWS account ID, real Cognito IDs, or NLB DNS values (use `<>` placeholders)
  - Do NOT include screenshots (those live in `docs/evidence/`)
  - Do NOT skip the Cost Estimate (assessor explicitly cares about cost discipline)
  - Do NOT auto-run destructive commands in Quick Start without `terraform plan` first (always plan-then-apply for assessor demonstration)
  - Do NOT promise features not actually implemented (e.g., don't claim "auto rollback" if Jenkinsfile doesn't have it)
  - Do NOT use emojis (professional tone for assessment context)
  - Do NOT exceed 600 lines (concise; deep-dive content stays in subdirectory READMEs)

  **Recommended Agent Profile**:
  - **Category**: `writing`
    - Reason: Pure documentation synthesis; aggregates information from all prior tasks into navigable entry point
  - **Skills**: []
    - Reason: No installed skill specializes in README authoring
  - **Skills Evaluated but Omitted**:
    - `terraform-style-guide`: Reviews HCL, not markdown
    - `frontend-code-review`: Wrong domain

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 9 (sequential, after T30 evidence consolidation)
  - **Blocks**: F1 audit (reads README to confirm D1-D6 mapping)
  - **Blocked By**: T1-T30 (must reference real paths and real Makefile targets)

  **References**:

  **Pattern References** (existing code to follow):
  - No existing README — create new
  - Subdirectory READMEs (e.g., `infra/envs/staging/README.md` from T3) follow same heading style as this file

  **API/Type References** (contracts to implement against):
  - All `make` targets defined across T1, T24, T28, T29, T30, T32 — README must match `Makefile` exactly
  - Variable names from `infra/envs/staging/terraform.tfvars.example` (T4) — README config section must match

  **Test References** (testing patterns to follow):
  - Documentation can be tested: `markdownlint`, link checking via `lychee`, command snippets via `bash -n` extraction

  **External References** (libraries and frameworks):
  - GitHub README best practices: `https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes`
  - Markdownlint rules: `https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md`
  - lychee link checker: `https://github.com/lycheeverse/lychee`
  - Awesome README examples: `https://github.com/matiassingers/awesome-readme`

  **WHY Each Reference Matters**:
  - GitHub README guide: ensures GitHub renders sections correctly (assessor will browse on GitHub)
  - Markdownlint: catches broken markdown (unclosed code blocks, mismatched headings) that breaks rendering
  - lychee: catches dead links to docs/ paths that get moved during refactor
  - Awesome README: structural inspiration for sectioning (TL;DR, Quick Start, Troubleshooting are conventional)

  **Acceptance Criteria**:
  - [ ] `/README.md` exists at repo root
  - [ ] All 16 sections present (verify with `grep -c "^##" README.md` ≥ 14)
  - [ ] `markdownlint README.md` → no errors (or `.markdownlint.json` documented exceptions)
  - [ ] `lychee --offline README.md` → all internal links resolve to existing files
  - [ ] No Vietnamese characters: `! grep -P "[\x{0080}-\x{024F}]" README.md` (ASCII + basic Latin only — adjust if extended chars needed)
  - [ ] No hardcoded account IDs: `! grep -E "[0-9]{12}" README.md`
  - [ ] No emojis: `! grep -P "[\x{1F300}-\x{1FAFF}]|[\x{2600}-\x{27BF}]" README.md`
  - [ ] Architecture image renders: `test -s docs/architecture.png`
  - [ ] D1-D6 table has 6 rows
  - [ ] Quick Start commands extractable: `grep -E "^[ ]*\$|^[ ]*make " README.md | wc -l` ≥ 10
  - [ ] Line count ≤ 600

  **QA Scenarios (MANDATORY)**:

  ```
  Scenario: README renders correctly + links valid (happy path)
    Tool: Bash
    Preconditions: All cross-referenced files exist (T1-T30 done)
    Steps:
      1. cd /home/ubuntu/Workspace/assessment
      2. markdownlint README.md > /tmp/lint.txt 2>&1; test $? -eq 0
      3. lychee --offline --no-progress README.md > /tmp/lychee.txt 2>&1; test $? -eq 0
      4. grep -c "^##" README.md | awk '{exit !($1 >= 14)}'
      5. wc -l README.md | awk '{exit !($1 <= 600)}'
      6. test -s docs/architecture.png && test -s docs/architecture.drawio
    Expected Result: lint clean, all internal links valid, ≥14 headings, ≤600 lines, architecture files present
    Failure Indicators: markdownlint fails (formatting issues), lychee fails (broken `docs/` links), missing architecture file
    Evidence: /tmp/lint.txt, /tmp/lychee.txt → keep as docs/evidence/00-readme-checks.txt

  Scenario: Quick Start commands are syntactically valid bash (negative = will fail to run)
    Tool: Bash
    Preconditions: README has "Quick Start" section
    Steps:
      1. # Extract code blocks under Quick Start heading
      2. awk '/^## Quick Start/,/^## /' README.md | grep -E "^(make |terraform |aws |kubectl )" > /tmp/quickstart-cmds.sh
      3. # Add shebang and check syntax
      4. echo '#!/bin/bash' | cat - /tmp/quickstart-cmds.sh > /tmp/qs-check.sh
      5. bash -n /tmp/qs-check.sh
    Expected Result: bash -n succeeds (no syntax errors in extracted commands)
    Failure Indicators: bash -n reports unmatched quote / paren / etc.
    Evidence: /tmp/qs-check.sh

  Scenario: D1-D6 deliverable links resolve (PDF mandate verification)
    Tool: Bash
    Preconditions: README has D1-D6 table
    Steps:
      1. test -s docs/architecture.drawio  # D1
      2. test -d infra/modules && test -f infra/envs/staging/main.tf  # D2
      3. test -d k8s/base && test -d k8s/overlays/staging  # D3
      4. test -s Jenkinsfile  # D4
      5. test -s docs/api-gateway-runbook.md && test -s docs/evidence/05-app/api-gateway-invoke-url.txt  # D5
      6. test -s docs/postman/max-weather.postman_collection.json  # D6
    Expected Result: All 6 paths exist and non-empty
    Failure Indicators: Any test fails → README claims a deliverable that doesn't exist
    Evidence: capture in docs/evidence/00-d1-d6-check.txt
  ```

  **Evidence to Capture**:
  - [ ] `/README.md` (the deliverable itself)
  - [ ] `Makefile` (referenced by README; updated cumulatively across T1, T24, T28, T29, T30, T32)
  - [ ] `docs/evidence/00-readme-checks.txt` (lint + lychee output)
  - [ ] `docs/evidence/00-d1-d6-check.txt` (D1-D6 link verification)

  **Commit**: YES (atomic README commit)
  - Message: `docs(readme): top-level project documentation + Makefile help`
  - Files: `README.md`, `Makefile` (final consolidation)
  - Pre-commit: `markdownlint README.md && lychee --offline --no-progress README.md && ! grep -E "[0-9]{12}" README.md`

- [x] 32. **Teardown automation: scripts/teardown.sh + cloud-nuke wrapper + Makefile target**

  **What to do**:
  - Create `scripts/teardown.sh` with strict ordering (reverse of build):
    - Phase 0: Confirmation prompt (`read -p "Type 'destroy max-weather' to confirm: "`) — abort if mismatched
    - Phase 1: **Application layer** — `kubectl delete -k k8s/overlays/staging --ignore-not-found` (removes Deployments, Services, Ingresses → triggers AWS LB Controller to clean target groups)
    - Phase 2: Wait for LB cleanup — `sleep 60` then `aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName,'max-weather')].LoadBalancerArn"` should be empty
    - Phase 3: **Helm releases** — `helm uninstall ingress-nginx -n ingress-nginx`, `helm uninstall cluster-autoscaler -n kube-system`, `helm uninstall fluent-bit -n amazon-cloudwatch`, `helm uninstall aws-load-balancer-controller -n kube-system`, `helm uninstall external-secrets -n external-secrets`, `helm uninstall metrics-server -n kube-system` (continue on error with `|| true`, log each)
    - Phase 4: **Namespaces** — `kubectl delete ns weather-staging weather-prod ingress-nginx amazon-cloudwatch external-secrets --ignore-not-found --timeout=120s`
    - Phase 5: **Manual API Gateway delete** — print instructions: "Open AWS Console → API Gateway → Delete `max-weather-api`. Press ENTER when done." (manual because it was created manually per T27)
    - Phase 6: **Terraform destroy** — `cd infra/envs/staging && terraform destroy -auto-approve` (handles EKS, VPC, NAT, IAM, ECR, Cognito, Secrets Manager, Lambda, CloudWatch log groups, Jenkins EC2, EIP)
    - Phase 7: **Bootstrap teardown** (optional) — print instructions: "To delete S3 backend + DynamoDB lock table, run `cd infra/bootstrap && terraform destroy -auto-approve` (only after confirming no other state files use them)"
    - Phase 8: **Cloud-nuke verification** — runs `cloud-nuke aws --region us-east-1 --resource-type ec2_security_group --resource-type ebs --resource-type elbv2 --resource-type lambda_function --resource-type cloudwatch_loggroup --resource-type cognito_userpool --dry-run` and prints any orphans; user confirms before actual nuke
    - Phase 9: Final report — list of resources destroyed, time elapsed, cost saved estimate
  - Create `scripts/cloud-nuke-wrapper.sh`:
    - Runs `cloud-nuke aws --region us-east-1 --config .cloud-nuke.yaml --dry-run` first
    - Shows count of resources to destroy
    - Requires explicit `--force` flag to proceed without confirmation
    - Excludes resources outside `max-weather` (use `.cloud-nuke.yaml` filter by tag `Project=max-weather`)
  - Create `.cloud-nuke.yaml` config:
    - Filter by name regex `.*max-weather.*` AND/OR tag `Project=max-weather`
    - Excludes: route53 hosted zones (assessor might have personal ones), KMS keys with deletion protection
  - Add `Makefile` targets:
    - `teardown`: invokes `scripts/teardown.sh` interactively
    - `teardown-force`: same but skips confirmation (use only in CI/scripted contexts; document warning)
    - `cloud-nuke-dry`: invokes wrapper with `--dry-run`
    - `cloud-nuke-force`: invokes wrapper with `--force` (last-resort cleanup)
  - Document in README "Teardown" section: order matters; if Phase 6 hangs, check VPC for orphan ENIs from LB Controller; if cloud-nuke finds orphans, investigate before destroying

  **Must NOT do**:
  - Do NOT auto-confirm without prompt — accidental teardown is unrecoverable
  - Do NOT cloud-nuke without `--dry-run` first AND explicit `--force` flag
  - Do NOT delete S3 bootstrap bucket automatically (user might have other state)
  - Do NOT use cloud-nuke without tag/name filter (would nuke unrelated resources in same account)
  - Do NOT skip Phase 2 wait — terraform destroy fails if LB target groups still exist (ENI leak)
  - Do NOT use `terraform destroy -refresh=false` (skipping refresh leaves orphans)
  - Do NOT call `aws iam delete-role` directly — let Terraform manage (otherwise state drift)
  - Do NOT commit `cloud-nuke_linux_amd64` binary — referenced by path or download in script
  - Do NOT use `set +e` to swallow errors silently — log and continue selectively only for known-OK failures

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Cross-tool orchestration (kubectl + helm + terraform + cloud-nuke + bash) requiring strict ordering and error handling
  - **Skills**: []
    - Reason: No installed skill specializes in destruction workflows
  - **Skills Evaluated but Omitted**:
    - `terraform-style-guide`: Reviews HCL only; teardown is bash + CLI orchestration

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 9 (sequential, last task before F1-F4)
  - **Blocks**: F3 cost+teardown verification (runs `make teardown` then validates AWS account is clean)
  - **Blocked By**: T1-T31 (cannot tear down what isn't built; also needs README to document teardown)

  **References**:

  **Pattern References** (existing code to follow):
  - No existing teardown — create new
  - Shell style matches `scripts/get-token.sh` (T28), `scripts/run-loadtest.sh` (T29), `scripts/verify-evidence.sh` (T30)

  **API/Type References** (contracts to implement against):
  - All Helm release names from T13-T18 (must match exactly for `helm uninstall`)
  - All namespace names from T19 (must match `kubectl delete ns`)
  - Terraform module structure from T3-T26 (destroy order: child modules first → root)
  - Resource naming convention `max-weather-*` and tag `Project=max-weather` (cloud-nuke filter relies on this)

  **Test References** (testing patterns to follow):
  - F3 cost+teardown reviewer (later) executes `make teardown` then runs `aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=max-weather` and asserts empty result

  **External References** (libraries and frameworks):
  - cloud-nuke filter config: `https://github.com/gruntwork-io/cloud-nuke#configuration`
  - terraform destroy guide: `https://developer.hashicorp.com/terraform/cli/commands/destroy`
  - kubectl delete propagation: `https://kubernetes.io/docs/tasks/administer-cluster/use-cascading-deletion/`
  - Helm uninstall: `https://helm.sh/docs/helm/helm_uninstall/`
  - AWS LB Controller cleanup behavior: `https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.8/deploy/installation/#uninstall`
  - aws elbv2 describe-load-balancers: `https://docs.aws.amazon.com/cli/latest/reference/elbv2/describe-load-balancers.html`

  **WHY Each Reference Matters**:
  - cloud-nuke config: filter syntax must match exactly (regex anchors, `^` and `$`) or filter silently fails → nukes everything
  - LB Controller cleanup: docs explicitly warn "delete Service/Ingress BEFORE uninstalling controller, else target groups orphan" → Phase 1 before Phase 3 ordering is critical
  - kubectl propagation: foreground vs background deletion affects whether LBs get cleanup time → use default (background) + Phase 2 sleep
  - terraform destroy: refresh-on-destroy ensures state matches reality before destroying (prevents "resource not found" partial destroys)

  **Acceptance Criteria**:
  - [ ] `scripts/teardown.sh` exists, executable, has `set -euo pipefail`, has confirmation prompt
  - [ ] `scripts/cloud-nuke-wrapper.sh` exists, executable, requires `--force` to bypass dry-run
  - [ ] `.cloud-nuke.yaml` exists with name regex `.*max-weather.*` filter
  - [ ] `bash -n scripts/teardown.sh && bash -n scripts/cloud-nuke-wrapper.sh` → no syntax errors
  - [ ] `shellcheck scripts/teardown.sh scripts/cloud-nuke-wrapper.sh` → clean (or documented exceptions)
  - [ ] Makefile has 4 teardown-related targets: `teardown`, `teardown-force`, `cloud-nuke-dry`, `cloud-nuke-force`
  - [ ] README "Teardown" section references these targets
  - [ ] After running `make teardown`: `aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=max-weather --region us-east-1 --query "ResourceTagMappingList[].ResourceARN" --output text` returns empty
  - [ ] After running `make teardown`: `kubectl get ns weather-staging` returns NotFound (or kubeconfig itself broken because cluster gone)
  - [ ] `cloud-nuke aws --region us-east-1 --config .cloud-nuke.yaml --dry-run` returns 0 resources after full teardown
  - [ ] `cloud-nuke_linux_amd64` is in `.gitignore` (verify with `git check-ignore cloud-nuke_linux_amd64`)

  **QA Scenarios (MANDATORY)**:

  ```
  Scenario: Teardown removes everything in correct order (happy path — DESTRUCTIVE)
    Tool: Bash
    Preconditions: All resources deployed, evidence already captured (T30 done), user has consented to teardown
    Steps:
      1. cd /home/ubuntu/Workspace/assessment
      2. echo "destroy max-weather" | bash scripts/teardown.sh 2>&1 | tee /tmp/teardown.log
      3. Assert exit 0: test ${PIPESTATUS[1]} -eq 0
      4. Assert phases logged: for p in "Phase 1" "Phase 3" "Phase 4" "Phase 6"; do grep -q "$p" /tmp/teardown.log; done
      5. Wait 30s for AWS eventual consistency
      6. aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=max-weather --region us-east-1 --query "ResourceTagMappingList[].ResourceARN" --output text > /tmp/remaining.txt
      7. Assert: test ! -s /tmp/remaining.txt  (file empty = no remaining resources)
    Expected Result: All phases logged, exit 0, zero remaining tagged resources
    Failure Indicators: terraform destroy errors (likely orphan ENIs), namespace deletion timeout (stuck finalizers), tagged resources remain (cloud-nuke needed)
    Evidence: /tmp/teardown.log → docs/evidence/09-teardown/teardown.log (created by teardown script itself)

  Scenario: Confirmation prompt rejects unconfirmed teardown (negative)
    Tool: Bash
    Preconditions: scripts/teardown.sh exists
    Steps:
      1. echo "wrong-text" | bash scripts/teardown.sh 2>&1 | tee /tmp/teardown-abort.log
      2. Assert exit non-zero: test ${PIPESTATUS[1]} -ne 0
      3. Assert no destruction commands ran: ! grep -E "(terraform destroy|helm uninstall|kubectl delete)" /tmp/teardown-abort.log
      4. Assert abort message: grep -qi "abort\|cancel\|confirmation failed" /tmp/teardown-abort.log
    Expected Result: Script aborts on wrong confirmation, no destructive command executed
    Failure Indicators: Script proceeds anyway (confirmation logic broken), no abort message
    Evidence: /tmp/teardown-abort.log

  Scenario: Cloud-nuke dry-run shows orphans without destroying (safety)
    Tool: Bash
    Preconditions: Some max-weather resources still exist (or simulated by tagging a test resource)
    Steps:
      1. bash scripts/cloud-nuke-wrapper.sh --dry-run 2>&1 | tee /tmp/nuke-dry.log
      2. Assert exit 0: test ${PIPESTATUS[1]} -eq 0
      3. Assert dry-run mode: grep -qi "dry.run\|will not actually" /tmp/nuke-dry.log
      4. Assert no actual deletion: ! grep -E "Deleted [0-9]+" /tmp/nuke-dry.log
    Expected Result: Lists candidates without destroying; exit 0
    Failure Indicators: Actually deletes (--force missing was honored), exits non-zero
    Evidence: /tmp/nuke-dry.log → docs/evidence/09-teardown/cloud-nuke-dry.log
  ```

  **Evidence to Capture**:
  - [ ] `scripts/teardown.sh`, `scripts/cloud-nuke-wrapper.sh`, `.cloud-nuke.yaml`
  - [ ] `Makefile` (4 teardown targets added)
  - [ ] `docs/evidence/09-teardown/teardown.log` (full teardown run output, captured by script)
  - [ ] `docs/evidence/09-teardown/cloud-nuke-dry.log` (dry-run output proving no orphans)
  - [ ] `docs/evidence/09-teardown/aws-tag-search-after.txt` (proves resourcegroupstaggingapi returns empty)

  **Commit**: YES (atomic teardown commit)
  - Message: `feat(teardown): scripts + cloud-nuke wrapper + Makefile targets`
  - Files: `scripts/teardown.sh`, `scripts/cloud-nuke-wrapper.sh`, `.cloud-nuke.yaml`, `Makefile`, `.gitignore` (ensure `cloud-nuke_linux_amd64` excluded)
  - Pre-commit: `bash -n scripts/teardown.sh scripts/cloud-nuke-wrapper.sh && shellcheck scripts/teardown.sh scripts/cloud-nuke-wrapper.sh && git check-ignore cloud-nuke_linux_amd64`

---

## Final Verification Wave (MANDATORY — after ALL implementation tasks)

> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.
>
> **Do NOT auto-proceed after verification. Wait for user's explicit approval before marking work complete.**

- [x] F1. **Plan Compliance Audit** — `oracle`
  Read this plan end-to-end. For each "Must Have": verify implementation exists by reading file / running curl / running terraform validate. For each "Must NOT Have": grep codebase for forbidden patterns (Karpenter, Istio, Prometheus, Stacks, hardcoded region in modules, committed secrets) — reject with file:line if found. Check evidence files exist in `docs/evidence/` and `.sisyphus/evidence/`. Compare deliverables D1–D6 against PDF requirements.
  Output: `Must Have [N/N] | Must NOT Have [N/N] | Tasks [N/N] | Deliverables [N/6] | VERDICT: APPROVE/REJECT`

- [x] F2. **Code Quality + Security Review** — `unspecified-high`
  Run `terraform fmt -check -recursive infra/`, `terraform validate` for staging env, `npm test` (or `bun test`) for app + lambda-authorizer, `kubectl apply --dry-run=client -f k8s/`, `gitleaks detect --source . --no-banner`. Review all changed files for: `as any`, hardcoded secrets, console.log in prod code, commented-out code, unused imports, oversized modules (>200 lines flag), AI slop (excessive comments, generic names, over-abstraction).
  Output: `terraform [PASS/FAIL] | tests [N pass/N fail] | k8s lint [PASS/FAIL] | gitleaks [N findings] | code review [N issues] | VERDICT`

- [x] F3. **Cost + Teardown Verification** — `unspecified-high`
  Run `aws sts get-caller-identity` to confirm account; `aws ec2 describe-instances --filters Name=instance-state-name,Values=running` (must be empty); `aws eks list-clusters` (must be empty); `aws elbv2 describe-load-balancers` (must be empty); `aws ce get-cost-and-usage --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) --granularity DAILY --metrics UnblendedCost`. Verify `scripts/teardown.sh` has account-ID assertion. Verify `cloud-nuke*` is in `.gitignore`.
  Output: `EC2 [N running] | EKS [N clusters] | LBs [N] | Cost-7d [$X] | Teardown script [SAFE/UNSAFE] | VERDICT`

- [x] F4. **Scope Fidelity Check** — `deep`
  For each task: read "What to do" + acceptance criteria, read actual diff via `git log --all --diff-filter=A` and `git diff main`. Verify 1:1 — everything in spec was built (no missing), nothing beyond spec was built (no scope creep). Check "Must NOT do" compliance especially: no real weather logic in app (≤200 LOC enforced), no frontend, no custom domain, no Karpenter/Istio/Prometheus, no Vietnamese in repo deliverables. Detect cross-task contamination.
  Output: `Tasks [N/N compliant] | LOC budget [app=X/200, authorizer=Y/150] | Forbidden patterns [CLEAN/N issues] | Language [English ONLY=YES/NO] | VERDICT`

---

## Commit Strategy

Use **conventional commits** with logical grouping (one PR-worthy commit per task or task-group).

Commit groups:
- **W0**: `chore: gitignore + pre-commit hooks + Makefile skeleton`
- **W1**: `docs(architecture): add system architecture diagram`
- **W2**: `feat(infra): bootstrap S3+DynamoDB for Terraform state`
- **W3**: One commit per module (`feat(infra/network)`, `feat(infra/iam)`, `feat(infra/ecr)`, `feat(infra/cognito)`, `feat(infra/cloudwatch)`, `feat(infra/lambda-authorizer)`)
- **W4**: `feat(infra/eks)`, `feat(infra/jenkins)`, `feat(infra/envs/staging): compose modules`
- **W5**:
  - `feat(app): node express weather-proxy with open-meteo`
  - `feat(lambda-authorizer): cognito jwt verifier`
  - `feat(k8s): deployment, service, ingress manifests`
  - `feat(k8s/nginx-controller): helm values for ingress controller`
  - `feat(ci): jenkinsfile and pipeline scripts`
  - `feat(postman): collection and environment template`
- **W6**: `feat(infra/cluster-bootstrap): metrics-server, cluster-autoscaler, fluent-bit, nginx ingress` + `chore(deploy): apply staging+prod manifests`
- **W7**: `docs(api-gateway): manual setup runbook with screenshots`
- **W8**:
  - `chore(evidence): hpa scaling load test results`
  - `chore(evidence): cloudwatch logs proof`
  - `docs: comprehensive readme with architecture, setup, demo, teardown`
- **W9**: `chore(teardown): cloud-nuke wrapper with account-id assertion`

Pre-commit on every commit: `gitleaks detect --staged --no-banner` (block on any finding).

---

## Success Criteria

### Verification Commands
```bash
# D1 — Architecture diagram
test -f docs/architecture.drawio && file docs/architecture.png | grep -q PNG  # Expected: exit 0

# D2 — Modular Terraform
cd infra/envs/staging && terraform init -backend=false && terraform validate && terraform fmt -check -recursive ../../  # Expected: exit 0
find infra/modules -mindepth 1 -maxdepth 1 -type d | wc -l  # Expected: >= 8
grep -rE 'us-east-1|"\d{12}"' infra/modules/ | wc -l  # Expected: 0 (no hardcoded region/account)

# D3 — K8s manifests
kubectl apply --dry-run=client -f k8s/deployment.yaml -f k8s/service.yaml -f k8s/ingress.yaml  # Expected: exit 0

# D4 — Jenkinsfile
grep -cE '^(pipeline|stage|steps)' Jenkinsfile  # Expected: >= 5

# D5 — API Gateway live
curl -sf -H "Authorization: Bearer $TOKEN" "$API_URL/weather?latitude=21.03&longitude=105.85" | jq -e '.current_weather' >/dev/null  # Expected: exit 0
curl -s -o /dev/null -w "%{http_code}" "$API_URL/weather?latitude=21.03&longitude=105.85"  # Expected: 401

# D6 — Postman demo
newman run docs/postman/max-weather.postman_collection.json -e docs/postman/staging.postman_environment.json  # Expected: exit 0

# Evidence — CloudWatch
aws logs filter-log-events --log-group-name /aws/eks/max-weather/application --start-time $(date -d '5 min ago' +%s)000 --query 'events | length(@)'  # Expected: > 0

# Evidence — HPA scaling
kubectl get hpa weather-api -n weather-prod -o json | jq -e '.status.currentReplicas > 3'  # Expected: exit 0

# Repo hygiene
gitleaks detect --source . --no-banner  # Expected: exit 0 (no findings)
git ls-files | grep -E 'cloud-nuke|\.tfstate$|\.env$|kubeconfig' | wc -l  # Expected: 0

# Teardown
aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text  # Expected: empty
aws eks list-clusters --query 'clusters | length(@)'  # Expected: 0
```

### Final Checklist
- [ ] All "Must Have" present (verified by F1)
- [ ] All "Must NOT Have" absent (verified by F1, F4)
- [ ] D1–D6 deliverables present and verified
- [ ] CloudWatch logs evidence captured (PDF mandate)
- [ ] HPA scaling evidence captured (PDF mandate)
- [ ] Public repo, no secrets leaked
- [ ] All AWS resources torn down (cost audit clean)
- [ ] README in English, all sections populated
- [ ] User explicit "okay" obtained after F1–F4 approve
