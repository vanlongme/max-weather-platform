output "function_arns" {
  description = "Map of function key to Lambda function ARN."
  value       = { for k, f in aws_lambda_function.this : k => f.arn }
}

output "function_names" {
  description = "Map of function key to Lambda function name."
  value       = { for k, f in aws_lambda_function.this : k => f.function_name }
}

output "function_invoke_arns" {
  description = "Map of function key to Lambda invoke ARN (for API Gateway integrations)."
  value       = { for k, f in aws_lambda_function.this : k => f.invoke_arn }
}

output "log_group_names" {
  description = "Map of function key to CloudWatch log group name."
  value       = { for k, g in aws_cloudwatch_log_group.function : k => g.name }
}
