# Max Weather Platform — Staging Environment
# Modules are appended by their respective tasks (T3-T15)
# Apply sequence:
#   Phase 1: terraform apply -var enable_irsa=false  (creates VPC + EKS + base IAM roles)
#   Phase 2: terraform apply -var enable_irsa=true   (adds IRSA roles after EKS OIDC is available)
