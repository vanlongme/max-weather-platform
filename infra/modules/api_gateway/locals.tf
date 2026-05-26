locals {
  nlb_listener_uri = "http://${var.nlb_dns}"

  vpc_link_enabled = length(var.vpc_link_subnet_ids) > 0

  integration_connection_type = local.vpc_link_enabled ? "VPC_LINK" : "INTERNET"

  integration_connection_id = local.vpc_link_enabled ? aws_apigatewayv2_vpc_link.this[0].id : null

  integration_uri_base = local.vpc_link_enabled ? var.nlb_listener_arn : local.nlb_listener_uri
}
