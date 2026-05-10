
## T7+T8+T9 (secrets, cloudwatch, cognito)
- AWS provider `~> 5.60` resolved to v5.100.0 — all resources used are stable.
- Pattern for module structure: `versions.tf` + `variables.tf` + `main.tf` + `outputs.tf` + `README.md` works cleanly with `terraform init -backend=false && terraform validate && terraform fmt -check`.
- `data "aws_region" "current" {}` lets cognito module construct token_endpoint/jwks_uri without hardcoding region — pattern reusable for other modules needing region.
- `lifecycle { ignore_changes = [secret_string] }` is the right pattern for secrets whose values are managed outside Terraform after bootstrap.
- `aws_cognito_user_pool_client.client_secret` is a sensitive output — must mark `sensitive = true`.

## T5+T6: IAM + ECR modules (2026-05-10)

- **IRSA two-phase pattern**: gating IRSA resources behind `count = var.oidc_provider_arn != "" ? 1 : 0` lets the IAM module be applied in phase 1 (no EKS yet) and phase 2 (EKS exists). Outputs use `try(aws_iam_role.x[0].arn, "")` to return empty string in phase 1.
- **Module file convention** (matches existing `networking/`): `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `README.md`. Provider pin: `hashicorp/aws ~> 5.60`, `terraform >= 1.9, < 2.0`.
- **AWS LB Controller policy** is large (~370 lines official); inlined the essential subset (ec2 Describe*, elasticloadbalancing:* read+mutate, iam:CreateServiceLinkedRole gated by service-name condition). Sufficient for ALB ingress; refresh from upstream `iam_policy.json` if features added.
- **ECR for_each + lifecycle policy**: drive both `aws_ecr_repository` and `aws_ecr_lifecycle_policy` with the same `toset(var.repositories)` so adding a repo name automatically extends both.
- **Lifecycle rule numbering**: `rulePriority` must be unique per rule; lower = evaluated first. `tagPrefixList` selectors only fire on tagged images, so the untagged-expiry rule needs `tagStatus = "untagged"` separately.
- **Validation**: `terraform init -backend=false && terraform validate && terraform fmt -check` is the cheap pre-commit triad for module-only dirs.
