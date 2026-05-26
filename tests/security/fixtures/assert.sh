#!/usr/bin/env bash
# assert.sh — verify a Jenkins build of a fixture branch produced the expected
# gate result.
#
# Usage: assert.sh <scanner> <jenkins-build-url> <expected-result>
#   <scanner>          : gitleaks | semgrep | trivy-fs | trivy-image | zap
#   <jenkins-build-url>: full URL to the specific build (e.g.
#                        https://jenkins.example.com/job/max-weather/job/fixture%2Fgitleaks/42/)
#   <expected-result>  : SUCCESS | FAILURE | UNSTABLE | ABORTED
#
# Curls <build-url>/api/json, reads `.result`, exits 0 on match, non-zero otherwise.
#
# Auth: if JENKINS_USER and JENKINS_TOKEN are set, they are used for basic auth.
set -euo pipefail

KNOWN_SCANNERS=(gitleaks semgrep trivy-fs trivy-image zap)
KNOWN_RESULTS=(SUCCESS FAILURE UNSTABLE ABORTED)

usage() {
  cat <<'EOF'
Usage: assert.sh <scanner> <jenkins-build-url> <expected-result>

Arguments:
  scanner             gitleaks | semgrep | trivy-fs | trivy-image | zap
  jenkins-build-url   Full URL of the Jenkins build (with or without trailing /)
  expected-result     SUCCESS | FAILURE | UNSTABLE | ABORTED

Environment:
  JENKINS_USER   Optional basic-auth username
  JENKINS_TOKEN  Optional basic-auth API token

Exit codes:
  0  result matches expected
  1  result does not match expected
  2  bad arguments
  3  Jenkins API unreachable or response malformed
EOF
}

log() {
  printf '[assert] %s\n' "$*" >&2
}

contains() {
  local needle="$1"; shift
  local item
  for item in "$@"; do
    if [[ "${item}" == "${needle}" ]]; then
      return 0
    fi
  done
  return 1
}

main() {
  if [[ $# -ne 3 ]]; then
    usage
    exit 2
  fi

  local scanner="$1"
  local build_url="$2"
  local expected="$3"

  if ! contains "${scanner}" "${KNOWN_SCANNERS[@]}"; then
    log "ERROR: unknown scanner '${scanner}'"
    usage
    exit 2
  fi

  if ! contains "${expected}" "${KNOWN_RESULTS[@]}"; then
    log "ERROR: expected-result must be one of: ${KNOWN_RESULTS[*]}"
    exit 2
  fi

  build_url="${build_url%/}"
  local api_url="${build_url}/api/json"

  local curl_args=(--silent --show-error --fail --location --max-time 30)
  if [[ -n "${JENKINS_USER:-}" && -n "${JENKINS_TOKEN:-}" ]]; then
    curl_args+=(--user "${JENKINS_USER}:${JENKINS_TOKEN}")
  fi

  log "GET ${api_url}"
  local body
  if ! body=$(curl "${curl_args[@]}" "${api_url}"); then
    log "ERROR: Jenkins API request failed"
    exit 3
  fi

  local result
  if command -v jq >/dev/null 2>&1; then
    result=$(printf '%s' "${body}" | jq -r '.result // "null"')
  else
    result=$(printf '%s' "${body}" \
      | grep -oE '"result"[[:space:]]*:[[:space:]]*("[^"]+"|null)' \
      | head -n1 \
      | sed -E 's/.*:[[:space:]]*"?([^"]+)"?$/\1/')
  fi

  if [[ -z "${result}" ]]; then
    log "ERROR: could not parse .result from Jenkins response"
    exit 3
  fi

  if [[ "${result}" == "null" ]]; then
    log "ERROR: build is still in progress (.result is null)"
    exit 3
  fi

  if [[ "${result}" == "${expected}" ]]; then
    log "PASS: scanner=${scanner} result=${result} (expected ${expected})"
    exit 0
  fi

  log "FAIL: scanner=${scanner} result=${result} expected=${expected}"
  exit 1
}

main "$@"
