resource "aws_apigatewayv2_api" "this" {
  name          = "${var.name}-api"
  protocol_type = "HTTP"
  tags          = var.tags
}

resource "aws_apigatewayv2_authorizer" "this" {
  api_id                            = aws_apigatewayv2_api.this.id
  authorizer_type                   = "REQUEST"
  name                              = "${var.name}-jwt-authorizer"
  authorizer_uri                    = "arn:aws:apigateway:${data.aws_region.current.region}:lambda:path/2015-03-31/functions/${var.lambda_authorizer_arn}/invocations"
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  authorizer_result_ttl_in_seconds  = 0
  identity_sources                  = ["$request.header.Authorization"]
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.this.id}/*/*/*"
}

resource "aws_apigatewayv2_stage" "this" {
  for_each = var.stages

  api_id      = aws_apigatewayv2_api.this.id
  name        = each.key
  auto_deploy = true
  tags        = var.tags
}

resource "null_resource" "delete_default_stage" {
  triggers = {
    api_id = aws_apigatewayv2_api.this.id
  }

  provisioner "local-exec" {
    command = "aws apigatewayv2 delete-stage --api-id ${self.triggers.api_id} --stage-name '$$default' 2>/dev/null || true"
  }

  depends_on = [
    aws_apigatewayv2_stage.this,
  ]
}

resource "aws_apigatewayv2_integration" "weather" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = "${local.nlb_listener_uri}/weather"
  connection_type    = "INTERNET"

  request_parameters = {
    "overwrite:header.Host" = var.ingress_host
    "overwrite:path"        = "/weather"
  }
}

resource "aws_apigatewayv2_integration" "healthz" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = "${local.nlb_listener_uri}/healthz"
  connection_type    = "INTERNET"

  request_parameters = {
    "overwrite:header.Host" = var.ingress_host
    "overwrite:path"        = "/healthz"
  }
}

resource "aws_apigatewayv2_route" "weather" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /weather"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.this.id
  target             = "integrations/${aws_apigatewayv2_integration.weather.id}"
}

resource "aws_apigatewayv2_route" "healthz" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /healthz"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.healthz.id}"
}
