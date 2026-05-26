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
KNOWN_SCANNERS=(gitleaks semgrep trivy-image)

usage() {
  cat <<'EOF'
Usage: provision.sh <subcommand>

Subcommands:
  gitleaks       Plant AWS docs canonical dummy key (app/canary-secret.txt)
  semgrep        Plant tainted-eval pattern (app/src/canary-eval.js)
  trivy-image    Add Dockerfile.canary using FROM node:14-alpine
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
    trivy-image)  plant_trivy_image ;;
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
