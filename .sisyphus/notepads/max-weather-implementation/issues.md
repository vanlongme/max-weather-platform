# Issues & Gotchas

## Session: ses_1ef2bfd10ffeHsnJqJbTP7ah77 — 2026-05-10

### Known Gotchas
- EKS apply takes 15-20 min — plan Wave 5 accordingly (parallel file authoring during apply)
- IRSA requires 2-phase apply (T5 creates roles, T10 creates EKS/OIDC, then re-apply attaches IRSA trust)
- NGINX creates NLB — must uninstall Helm BEFORE terraform destroy (LB Controller cleans target groups)
- HPA needs metrics-server — install before evidence collection
- Fluent Bit IRSA role must trust the OIDC endpoint of the EKS cluster (created in T10)
- OpenMeteo cached responses may keep CPU low → load test may not organically trigger HPA scale-up
  → Fallback: kubectl scale --replicas=5 to demonstrate scale-up path

### Pre-commit Notes
- gitleaks uses ~/.config/gitleaks/.allowlist for known test keys
- terraform_fmt hook rewrites files — must `git add` after hook runs to include rewrites in commit
