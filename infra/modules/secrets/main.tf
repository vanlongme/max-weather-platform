resource "aws_secretsmanager_secret" "secrets" {
  for_each = var.secrets

  name                    = replace(each.value.name, "__CLUSTER_NAME__", var.cluster_name)
  description             = each.value.description
  recovery_window_in_days = each.value.recovery_window_in_days

  tags = merge(var.tags, {
    Name = replace(each.value.name, "__CLUSTER_NAME__", var.cluster_name)
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
