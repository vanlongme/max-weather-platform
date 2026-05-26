#!/usr/bin/env bash
# provision.sh — plant canary findings on fixture/<scanner> branches.
#
# Each subcommand:
#   1. checks out main
#   2. force-recreates branch fixture/<scanner>
#   3. applies one deterministic mutation
#   4. commits "chore(fixture): plant <scanner> finding"
#   5. force-pushes fixture/<scanner> to origin
#
# `teardown` deletes all fixture/* branches on origin.
#
# Safety:
#   - Mutations are committed only on fixture/<scanner> branches, never on main.
#   - Planted findings use canonical dummy data (AWS docs example key, EOL base
#     image, historical lodash advisory pin, textbook tainted-eval, missing header).
#   - No real secrets, no exploitable code, no production endpoints.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

REMOTE="${REMOTE:-origin}"
MAIN_BRANCH="${MAIN_BRANCH:-main}"
KNOWN_SCANNERS=(gitleaks semgrep trivy-fs trivy-image zap)

usage() {
  cat <<'EOF'
Usage: provision.sh <subcommand>

Subcommands:
  gitleaks       Plant AWS docs canonical dummy key (app/canary-secret.txt)
  semgrep        Plant tainted-eval pattern (app/src/canary-eval.js)
  trivy-fs       Pin lodash@4.17.4 in app/package.json
  trivy-image    Add Dockerfile.canary using FROM node:14-alpine
  zap            Add middleware that drops X-Content-Type-Options
  teardown       Delete all fixture/<scanner> branches on origin
  -h, --help     Show this help

Environment:
  REMOTE         Git remote (default: origin)
  MAIN_BRANCH    Base branch (default: main)
EOF
}

log() {
  printf '[provision] %s\n' "$*" >&2
}

start_branch() {
  local scanner="$1"
  local branch="fixture/${scanner}"

  log "Resetting to ${MAIN_BRANCH}"
  git fetch "${REMOTE}" "${MAIN_BRANCH}" --quiet
  git checkout "${MAIN_BRANCH}" --quiet
  git reset --hard "${REMOTE}/${MAIN_BRANCH}" --quiet

  log "Recreating local branch ${branch}"
  git branch -D "${branch}" 2>/dev/null || true
  git checkout -b "${branch}" --quiet
}

commit_and_push() {
  local scanner="$1"
  local branch="fixture/${scanner}"

  git add -A
  git commit -m "chore(fixture): plant ${scanner} finding" --quiet
  log "Force-pushing ${branch} to ${REMOTE}"
  git push "${REMOTE}" "${branch}" --force
}

plant_gitleaks() {
  start_branch "gitleaks"
  # NOTE: tests/security/fixtures/** is allowlisted in .gitleaks.toml, so the
  # canary secret must live outside that path. app/ is in scope for gitleaks.
  local target="app/canary-secret.txt"
  cat > "${target}" <<'EOF'
# CANARY FIXTURE — DO NOT MERGE
# AWS-documentation canonical example key (not provisioned, never valid).
# Source: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_identifiers.html
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
EOF
  commit_and_push "gitleaks"
}

plant_semgrep() {
  start_branch "semgrep"
  local target="app/src/canary-eval.js"
  mkdir -p "$(dirname "${target}")"
  cat > "${target}" <<'EOF'
// CANARY FIXTURE — DO NOT MERGE
// Tainted-eval pattern matched by Semgrep p/nodejs ruleset
// (rule: javascript.lang.security.audit.eval-detected.eval-detected).
module.exports = function canaryRoute(req, res) {
  // eslint-disable-next-line no-eval
  const result = eval(req.query.input);
  res.json({ result });
};
EOF
  commit_and_push "semgrep"
}

plant_trivy_fs() {
  start_branch "trivy-fs"
  local target="app/package.json"
  if [[ ! -f "${target}" ]]; then
    log "ERROR: ${target} not found; cannot plant trivy-fs fixture"
    exit 1
  fi
  # Pin to lodash@4.17.4 (multiple historical advisories: CVE-2018-3721,
  # CVE-2019-10744, etc.). Uses python -c for deterministic JSON edit; falls
  # back to node if python3 missing.
  if command -v python3 >/dev/null 2>&1; then
    python3 - "${target}" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f:
    pkg = json.load(f)
pkg.setdefault("dependencies", {})["lodash"] = "4.17.4"
with open(p, "w") as f:
    json.dump(pkg, f, indent=2)
    f.write("\n")
PY
  else
    node -e '
      const fs = require("fs");
      const p = process.argv[1];
      const pkg = JSON.parse(fs.readFileSync(p, "utf8"));
      pkg.dependencies = pkg.dependencies || {};
      pkg.dependencies.lodash = "4.17.4";
      fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + "\n");
    ' "${target}"
  fi
  commit_and_push "trivy-fs"
}

plant_trivy_image() {
  start_branch "trivy-image"
  local target="tests/security/fixtures/Dockerfile.canary"
  mkdir -p "$(dirname "${target}")"
  cat > "${target}" <<'EOF'
# CANARY FIXTURE — DO NOT MERGE
# node:14-alpine is EOL and ships with multiple known CVEs that Trivy will
# surface. Used only to validate that the image scan gate fires.
FROM node:14-alpine
WORKDIR /app
COPY . .
CMD ["node", "--version"]
EOF
  commit_and_push "trivy-image"
}

plant_zap() {
  start_branch "zap"
  local target="app/src/middleware/canary-headers.js"
  mkdir -p "$(dirname "${target}")"
  cat > "${target}" <<'EOF'
// CANARY FIXTURE — DO NOT MERGE
// Strips X-Content-Type-Options before responses leave the app, which makes
// OWASP ZAP baseline scan raise the "X-Content-Type-Options Header Missing"
// alert. Wire this middleware into the Express app on the fixture branch only.
module.exports = function canaryHeaderStripper(_req, res, next) {
  const origSetHeader = res.setHeader.bind(res);
  res.setHeader = function patched(name, value) {
    if (typeof name === "string" && name.toLowerCase() === "x-content-type-options") {
      return res;
    }
    return origSetHeader(name, value);
  };
  res.removeHeader("X-Content-Type-Options");
  next();
};
EOF
  commit_and_push "zap"
}

teardown() {
  log "Deleting fixture/* branches on ${REMOTE}"
  git fetch "${REMOTE}" --prune --quiet
  local scanner branch
  local failed=0
  for scanner in "${KNOWN_SCANNERS[@]}"; do
    branch="fixture/${scanner}"
    if git ls-remote --exit-code --heads "${REMOTE}" "${branch}" >/dev/null 2>&1; then
      log "Deleting ${REMOTE}/${branch}"
      if ! git push "${REMOTE}" --delete "${branch}"; then
        log "WARN: failed to delete ${branch}"
        failed=1
      fi
    else
      log "Skip ${branch} (not on ${REMOTE})"
    fi
    git branch -D "${branch}" 2>/dev/null || true
  done
  git checkout "${MAIN_BRANCH}" --quiet 2>/dev/null || true
  return "${failed}"
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 2
  fi

  case "$1" in
    gitleaks)     plant_gitleaks ;;
    semgrep)      plant_semgrep ;;
    trivy-fs)     plant_trivy_fs ;;
    trivy-image)  plant_trivy_image ;;
    zap)          plant_zap ;;
    teardown)     teardown ;;
    -h|--help)    usage ;;
    *)
      log "ERROR: unknown subcommand '$1'"
      usage
      exit 2
      ;;
  esac
}

main "$@"
