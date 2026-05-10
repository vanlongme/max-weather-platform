locals {
  # Environment is derived from this composition's directory name.
  # e.g. infra/envs/poc -> "poc", infra/envs/staging -> "staging".
  environment = basename(path.module)

  # master_prefix is the canonical prefix applied to every resource name
  # produced by this composition. Format: "<environment>-<project>".
  # e.g. "poc-max-weather".
  master_prefix = "${local.environment}-${var.project}"

  common_tags = {
    Project     = var.project
    Environment = local.environment
    ManagedBy   = "terraform"
  }
}
