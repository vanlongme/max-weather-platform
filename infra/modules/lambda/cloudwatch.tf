resource "aws_cloudwatch_log_group" "function" {
  for_each = var.functions

  name              = "/aws/lambda/${var.name}-${each.key}${each.value.function_name_suffix}"
  retention_in_days = each.value.log_retention_days

  tags = merge(var.tags, {
    Name = "/aws/lambda/${var.name}-${each.key}${each.value.function_name_suffix}"
  })
}
