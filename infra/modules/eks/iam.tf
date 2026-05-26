# iam resources for the EKS module.

# ──────────────────────────────────────────
# Cluster IAM role
# ──────────────────────────────────────────

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_resource_controller" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSVPCResourceController"
}

resource "aws_iam_role_policy_attachment" "cluster_compute_policy" {
  count      = var.enable_auto_mode ? 1 : 0
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSComputePolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_block_storage_policy" {
  count      = var.enable_auto_mode ? 1 : 0
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSBlockStoragePolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_load_balancing_policy" {
  count      = var.enable_auto_mode ? 1 : 0
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSLoadBalancingPolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_networking_policy" {
  count      = var.enable_auto_mode ? 1 : 0
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSNetworkingPolicy"
}

# ──────────────────────────────────────────
# Node IAM role
# ──────────────────────────────────────────

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "node" {
  name               = "${local.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-node-role"
  })
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_readonly" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ──────────────────────────────────────────
# Fargate IAM role (created always; used only when fargate_profiles non-empty)
# ──────────────────────────────────────────

data "aws_iam_policy_document" "fargate_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["eks-fargate-pods.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "fargate" {
  name               = "${local.cluster_name}-fargate-role"
  assume_role_policy = data.aws_iam_policy_document.fargate_assume_role.json

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-fargate-role"
  })
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution" {
  role       = aws_iam_role.fargate.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

# ──────────────────────────────────────────
# EBS CSI Controller IAM role (Pod Identity)
# ──────────────────────────────────────────

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  count = var.enable_ebs_csi_addon ? 1 : 0

  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole", "sts:TagSession"]
  }
}

resource "aws_iam_role" "ebs_csi_controller" {
  count = var.enable_ebs_csi_addon ? 1 : 0

  name               = "${local.cluster_name}-ebs-csi-controller-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role[0].json

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-ebs-csi-controller-role"
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  count = var.enable_ebs_csi_addon ? 1 : 0

  role       = aws_iam_role.ebs_csi_controller[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ──────────────────────────────────────────
# EFS CSI Controller IAM role (Pod Identity)
# ──────────────────────────────────────────

data "aws_iam_policy_document" "efs_csi_assume_role" {
  count = var.enable_efs_csi_addon ? 1 : 0

  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole", "sts:TagSession"]
  }
}

resource "aws_iam_role" "efs_csi_controller" {
  count = var.enable_efs_csi_addon ? 1 : 0

  name               = "${local.cluster_name}-efs-csi-controller-role"
  assume_role_policy = data.aws_iam_policy_document.efs_csi_assume_role[0].json

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-efs-csi-controller-role"
  })
}

resource "aws_iam_role_policy_attachment" "efs_csi_policy" {
  count = var.enable_efs_csi_addon ? 1 : 0

  role       = aws_iam_role.efs_csi_controller[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}
