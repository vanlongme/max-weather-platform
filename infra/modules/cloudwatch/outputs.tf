output "log_group_names" {
  description = "Map of log group key to CloudWatch log group name."
  value       = { for k, v in aws_cloudwatch_log_group.groups : k => v.name }
}

output "log_group_arns" {
  description = "Map of log group key to CloudWatch log group ARN."
  value       = { for k, v in aws_cloudwatch_log_group.groups : k => v.arn }
}

output "eks_application_log_group" {
  description = "Name of the EKS application log group (for Fluent Bit config)."
  value       = aws_cloudwatch_log_group.groups["eks_application"].name
}

output "lambda_authorizer_log_group" {
  description = "Name of the Lambda authorizer log group."
  value       = aws_cloudwatch_log_group.groups["lambda_authorizer"].name
}

output "api_gateway_log_group" {
  description = "Name of the API Gateway access log group."
  value       = aws_cloudwatch_log_group.groups["api_gateway"].name
}
