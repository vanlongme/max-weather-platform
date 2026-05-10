resource "aws_eks_node_group" "main" {
  cluster_name    = var.cluster_name
  node_group_name = "${var.cluster_name}-general"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.instance_types
  capacity_type  = "ON_DEMAND"
  disk_size      = var.disk_size
  ami_type       = "AL2023_x86_64_STANDARD"

  scaling_config {
    min_size     = var.min_size
    max_size     = var.max_size
    desired_size = var.desired_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "general"
  }

  tags = merge(var.tags, {
    Name                                            = "${var.cluster_name}-general"
    "k8s.io/cluster-autoscaler/enabled"             = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
  })

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
