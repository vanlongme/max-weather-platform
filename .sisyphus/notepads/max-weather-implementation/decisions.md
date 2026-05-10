# Decisions

## Session: ses_1ef2bfd10ffeHsnJqJbTP7ah77 — 2026-05-10

### Architecture
- Single NAT GW (cost) — not HA NAT
- TLS terminated at API Gateway; internal NLB→NGINX→pods is HTTP
- EKS API endpoint: public but restricted to operator IP (not 0.0.0.0/0)
- Lambda authorizer payload v2.0 SIMPLE response mode
- Postman collection v2.1.0 format

### Terraform
- Local backend for bootstrap (chicken-and-egg)
- random_id suffix for globally unique S3 bucket names
- .terraform.lock.hcl MUST be committed (NOT gitignored)
- No Terraform Stacks / HCP Terraform
- All modules: no hardcoded region/account — only in envs/staging/terraform.tfvars

### CI/CD
- Jenkins pipeline scope: staging only; prod manual
- Jenkins SG: operator IP /32 only, never 0.0.0.0/0
- Jenkins EIP for stable demo URL
- No static AWS keys in Jenkins — IAM instance profile only

### Deployment
- Lambda chicken-and-egg: Terraform creates with placeholder inline code; T24 updates with real ZIP
- kubectl set image after kubectl apply -k (SHA pinning)
- k6 load test via NLB DNS directly (bypass API GW throttle)

### Evidence
- Evidence committed to docs/evidence/ for repo deliverable
- Also saved to .sisyphus/evidence/ for internal tracking
- Sanitize terraform outputs before commit (strip secrets via jq)
