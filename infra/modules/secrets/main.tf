locals {
  secret_names = {
    for key, cfg in var.secrets :
    key => replace(coalesce(cfg.name, "${var.name}-${key}-secret"), var.cluster_name_placeholder, var.name)
  }
}

resource "aws_secretsmanager_secret" "secrets" {
  for_each = var.secrets

  name                    = local.secret_names[each.key]
  description             = each.value.description
  recovery_window_in_days = each.value.recovery_window_in_days

  tags = merge(var.tags, {
    Name = local.secret_names[each.key]
  })
}

resource "aws_secretsmanager_secret_version" "secrets" {
  for_each = { for k, v in var.secrets : k => v if v.initial_value != null }

  secret_id     = aws_secretsmanager_secret.secrets[each.key].id
  secret_string = each.value.initial_value

  lifecycle {
    ignore_changes = [secret_string]
  }
}
