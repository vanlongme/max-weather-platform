# cloudwatch resources for the EKS module.

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "/aws/eks/${local.cluster_name}/cluster"
  })
}
