resource "aws_cloudwatch_log_group" "groups" {
  for_each = var.log_groups

  name              = replace(each.value.name, "__CLUSTER_NAME__", var.cluster_name)
  retention_in_days = coalesce(each.value.retention_days, var.log_retention_days)
  tags = merge(var.tags, {
    Name = replace(each.value.name, "__CLUSTER_NAME__", var.cluster_name)
  })
}
