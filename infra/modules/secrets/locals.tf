locals {
  secret_names = {
    for key, cfg in var.secrets :
    key => replace(coalesce(cfg.name, "${var.name}-${key}-secret"), var.cluster_name_placeholder, var.name)
  }
}
