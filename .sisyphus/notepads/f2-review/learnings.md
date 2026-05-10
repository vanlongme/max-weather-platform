
## F2 Review Findings (2026-05-10)

- All automated checks pass (fmt, validate, app tests 6/6, lambda tests 5/5, kustomize, script syntax 9/9).
- gitleaks not installed in environment - skipped.
- HPA target is 60% averageUtilization (plan asked 70%). Slight deviation, both reasonable.
- server.js uses /healthz (not /health) - tests align. Plan originally said /health, but /healthz is more standard.
- Lambda authorizer correctly uses lazy jwksClient init via getClient().
- Authorizer checks token_use=='access' and scope contains weather-api/read.
- No hardcoded region/pool IDs - all from env.
- teardown.sh has confirmation gate, no `set -x`, ordered phases correct.
- get-token.sh has `set +x`, exits non-zero on missing token, never prints token to stdout alongside other content.
- Makefile help works, all targets in .PHONY.
- .cloud-nuke.yaml properly scoped via names_regex to max-weather/weather-api.
- No TODO/FIXME/HACK/PLACEHOLDER in production code.
- All functions <50 lines.
