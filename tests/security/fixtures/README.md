# Security Gate Canary Fixtures

Canary fixture branches that intentionally plant a single, well-known finding for each
scanner in the Jenkins security pipeline (gitleaks / semgrep / trivy image scan).
Used to validate that each scanner actually fires (no silent skips, no broken rule sets)
without ever touching `main` and without planting real exploitable code or live secrets.

## Safety

- All planted findings use **canonical, public, well-documented dummy data**:
  - `AKIAIOSFODNN7EXAMPLE` — the AWS-documentation example access key (not provisioned)
  - `eval(req.query.input)` — textbook tainted-eval pattern matched by `p/nodejs`
  - `node:14-alpine` — EOL base image known to surface CVEs in Trivy
- Mutations are committed only to `fixture/<scanner>` branches, **never** to `main`.
- `teardown` deletes every `fixture/*` branch on `origin` cleanly.
- No real secrets, no production endpoints, no exploitable payloads.

## Branch lifecycle

```
main ──┬─ fixture/gitleaks    (plant dummy AWS key)        ─┐  Jenkins multibranch
       ├─ fixture/semgrep     (plant tainted eval)          ├─ picks up branch,
       └─ fixture/trivy-image (plant old base image)       ─┘  runs gates, fails
                  │
                  └── provision.sh teardown → branches deleted on origin
```

Each subcommand is idempotent: it force-checks out `main`, recreates the fixture branch
from scratch, applies the mutation, commits, and force-pushes. Running a subcommand twice
yields the same remote branch state.

## Usage

```bash
chmod +x tests/security/fixtures/provision.sh
chmod +x tests/security/fixtures/assert.sh

# Plant a single canary
./tests/security/fixtures/provision.sh gitleaks
./tests/security/fixtures/provision.sh semgrep
./tests/security/fixtures/provision.sh trivy-image

# Trigger Jenkins build of the branch manually or via webhook,
# then assert the build outcome matches the expectation:
./tests/security/fixtures/assert.sh gitleaks    https://jenkins.example.com/job/max-weather/job/fixture%252Fgitleaks/42/    FAILURE
./tests/security/fixtures/assert.sh semgrep     https://jenkins.example.com/job/max-weather/job/fixture%252Fsemgrep/17/     FAILURE
./tests/security/fixtures/assert.sh trivy-image https://jenkins.example.com/job/max-weather/job/fixture%252Ftrivy-image/4/  FAILURE

# Clean up all fixture branches on origin
./tests/security/fixtures/provision.sh teardown
```

`assert.sh` curls `<jenkins-build-url>/api/json`, reads `.result`, and exits non-zero
on mismatch. Pass `SUCCESS` as the expected result for negative-control runs (e.g. to
verify a scanner is *not* over-eagerly failing clean code).

## Subcommands

| Subcommand    | Branch                 | Mutation                                                           | Detected by   |
|---------------|------------------------|--------------------------------------------------------------------|---------------|
| `gitleaks`    | `fixture/gitleaks`     | `app/canary-secret.txt` containing `AKIAIOSFODNN7EXAMPLE`          | gitleaks      |
| `semgrep`     | `fixture/semgrep`      | `app/src/canary-eval.js` with `eval(req.query.input)`              | semgrep       |
| `trivy-image` | `fixture/trivy-image`  | `tests/security/fixtures/Dockerfile.canary` `FROM node:14-alpine`  | trivy image   |
| `teardown`    | n/a                    | Deletes all `fixture/*` branches on `origin`                       | n/a           |

### gitleaks fixture path note

`.gitleaks.toml` allowlist excludes `tests/security/fixtures/**` from secret scans
(prevents the *other* canary fixtures here from triggering gitleaks). The gitleaks
fixture therefore **must** plant its dummy key outside that allowlisted path —
`app/canary-secret.txt`. Do not move it into `tests/security/fixtures/` or it will
be silently allowlisted and the gate validation breaks.

## Pass criteria

- `provision.sh <scanner>` creates `fixture/<scanner>` on origin with exactly one new commit
  beyond `main`, message `chore(fixture): plant <scanner> finding`.
- Jenkins build of `fixture/<scanner>` produces the expected gate result (typically `FAILURE`).
- `assert.sh <scanner> <build-url> <expected>` exits 0 when the Jenkins API `.result`
  matches `<expected>`.
- `provision.sh teardown` removes every `fixture/*` branch from origin and leaves the
  local checkout on `main`.

## Files

- `provision.sh`  — subcommands: `gitleaks | semgrep | trivy-image | teardown`
- `assert.sh`     — `<scanner> <jenkins-build-url> <SUCCESS|FAILURE|UNSTABLE|ABORTED>`
- `README.md`     — this file
