output "api_id" {
  description = "ID of the HTTP API."
  value       = aws_apigatewayv2_api.this.id
}

output "invoke_urls" {
  description = "Map of stage name to invoke URL."
  value = {
    for stage_name, _ in var.stages :
    stage_name => "https://${aws_apigatewayv2_api.this.id}.execute-api.${data.aws_region.current.region}.amazonaws.com/${stage_name}"
  }
}

output "authorizer_id" {
  description = "ID of the Lambda authorizer."
  value       = aws_apigatewayv2_authorizer.this.id
}
