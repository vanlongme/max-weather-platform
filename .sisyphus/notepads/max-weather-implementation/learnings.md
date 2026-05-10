# Learnings

## Session: ses_1ef2bfd10ffeHsnJqJbTP7ah77 — 2026-05-10

### Key Conventions
- Region: us-east-1
- Cluster name: max-weather
- VPC CIDR: 10.20.0.0/16
- Namespaces: weather-staging, weather-prod
- EKS version: 1.30
- Node type: t3.medium, 2-10, ON_DEMAND, AL2023
- Terraform versions: >= 1.9 < 2.0, aws ~> 5.60
- Image tags: staging-<sha>+latest for staging; prod-<sha> for prod
- Cognito scope: weather-api/read
- NGINX Helm chart: 4.11.3
- Cluster Autoscaler: 9.37.0
- aws-for-fluent-bit: 0.1.34
- aws-load-balancer-controller: 1.8.2
- external-secrets: 0.10.4
- metrics-server: 3.12.1

### Shell/Tooling
- Use `set -euo pipefail` in all scripts
- cloud-nuke binary at /home/ubuntu/Workspace/assessment/cloud-nuke_linux_amd64 — NEVER commit
- gitleaks must pass before every commit

## Task T2 — Architecture Diagram (drawio + png)
- `xmllint` is NOT installed on this box; use `python3 -c "import xml.etree.ElementTree as ET; ET.parse(...)"` for XML well-formedness checks.
- `drawio` CLI is at `/usr/bin/drawio` and requires X server; use `xvfb-run -a drawio --no-sandbox -x -f png -e -b 10 -o <out.png> <in.drawio>` for headless export.
- Native drawio file uses `<mxfile>` wrapper around `<diagram><mxGraphModel>...</mxGraphModel></diagram></mxfile>` — that wrapper is what makes it openable in app.diagrams.net.
- Embedded XML (`-e`) keeps the PNG editable in draw.io.

## T4 — Networking module (2026-05-10)
- Module path: `infra/modules/networking/` (not `terraform/modules/...` — repo uses `infra/`)
- Terraform v1.14.0 available locally; AWS provider 5.100.0 installed under `~> 5.60`
- `terraform init -backend=false` + `terraform validate` + `terraform fmt -check` all exit 0
- Subnets keyed by AZ index via `count`; route tables created per-AZ even with `single_nat_gateway = true` (one private RT per AZ all pointing to NAT[0])
- VPC endpoints: 3 Interface (ecr.api / ecr.dkr / logs) + 1 Gateway (s3); SG allows 443 from VPC CIDR only
- Subnet tagging: `kubernetes.io/role/elb` on public, `kubernetes.io/role/internal-elb` on private, plus `kubernetes.io/cluster/<name>=shared` on both for EKS LB controller auto-discovery
- Used `aws_eip.domain = "vpc"` (not deprecated `vpc = true`)
