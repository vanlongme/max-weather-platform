data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

data "aws_eks_cluster_auth" "this" {
  name = aws_eks_cluster.this.name
}
