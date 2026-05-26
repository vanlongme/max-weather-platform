resource "aws_lambda_function" "this" {
  for_each = var.functions

  function_name    = "${var.name}-${each.key}${each.value.function_name_suffix}"
  description      = "Lambda function ${each.key} managed by Terraform"
  role             = each.value.role_arn
  handler          = each.value.handler
  runtime          = each.value.runtime
  memory_size      = each.value.memory_size
  timeout          = each.value.timeout
  filename         = data.archive_file.function[each.key].output_path
  source_code_hash = data.archive_file.function[each.key].output_base64sha256

  dynamic "environment" {
    for_each = length(each.value.environment) > 0 ? [each.value.environment] : []
    content {
      variables = environment.value
    }
  }

  depends_on = [aws_cloudwatch_log_group.function]

  tags = merge(var.tags, {
    Name = "${var.name}-${each.key}${each.value.function_name_suffix}"
  })
}

resource "aws_lambda_permission" "invoke" {
  for_each = merge([
    for fn_key, fn_val in var.functions : {
      for label, source_arn in fn_val.invoke_principals : "${fn_key}|${label}" => {
        function_key = fn_key
        source_arn   = source_arn
      }
    }
  ]...)

  statement_id  = "Allow-${replace(each.key, "|", "-")}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this[each.value.function_key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = each.value.source_arn
}
