resource "aws_apigatewayv2_api" "this" {
  name          = "${var.name}-api"
  protocol_type = "HTTP"
  tags          = var.tags
}

resource "aws_apigatewayv2_vpc_link" "this" {
  count = local.vpc_link_enabled ? 1 : 0

  name               = "${var.name}-vpclink"
  subnet_ids         = var.vpc_link_subnet_ids
  security_group_ids = var.vpc_link_security_group_ids
  tags               = var.tags
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

resource "aws_apigatewayv2_stage" "this" {
  for_each = var.stages

  api_id      = aws_apigatewayv2_api.this.id
  name        = each.key
  auto_deploy = true
  tags        = var.tags
}

resource "aws_apigatewayv2_integration" "weather" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = local.vpc_link_enabled ? local.integration_uri_base : "${local.integration_uri_base}/weather"
  connection_type    = local.integration_connection_type
  connection_id      = local.integration_connection_id

  request_parameters = {
    "overwrite:header.Host" = var.ingress_host
    "overwrite:path"        = "/weather"
  }
}

resource "aws_apigatewayv2_integration" "healthz" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = local.vpc_link_enabled ? local.integration_uri_base : "${local.integration_uri_base}/healthz"
  connection_type    = local.integration_connection_type
  connection_id      = local.integration_connection_id

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
