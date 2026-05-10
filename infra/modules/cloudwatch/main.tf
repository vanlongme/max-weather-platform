locals {
  log_groups = {
    eks_application   = "/aws/eks/${var.cluster_name}/application"
    eks_control_plane = "/aws/eks/${var.cluster_name}/cluster"
    lambda_authorizer = "/aws/lambda/${var.cluster_name}-authorizer"
    api_gateway       = "/aws/apigateway/${var.cluster_name}-api"
    jenkins           = "/aws/ec2/${var.cluster_name}-jenkins"
  }
}

resource "aws_cloudwatch_log_group" "groups" {
  for_each          = local.log_groups
  name              = each.value
  retention_in_days = var.log_retention_days
  tags              = merge(var.tags, { Name = each.value })
}
