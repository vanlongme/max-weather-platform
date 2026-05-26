# karpenter resources for the EKS module.
# Native rewrite of terraform-aws-modules/eks/aws v21.20.0 karpenter sub-module.
# Policy statements transcribed from upstream policy.tf with substitutions documented inline.

# ──────────────────────────────────────────
# Region data source (used in policy ARNs)
# ──────────────────────────────────────────

data "aws_region" "current" {}

# ──────────────────────────────────────────
# Controller IAM policy documents (transcribed from upstream policy.tf)
# Split into TWO documents (ec2 + iam) because the combined policy JSON
# exceeds the 6144-char IAM managed policy quota.
# UPSTREAM_SUB: local.partition -> data.aws_partition.current.partition
# UPSTREAM_SUB: local.region -> data.aws_region.current.region
# UPSTREAM_SUB: var.cluster_name -> aws_eks_cluster.this.name
# UPSTREAM_SUB: local.account_id -> data.aws_caller_identity.current.account_id
# UPSTREAM_SUB: aws_iam_role.node[0].arn -> aws_iam_role.karpenter_node.arn
# UPSTREAM_SUB: aws_sqs_queue.this[0].arn -> aws_sqs_queue.karpenter.arn
# UPSTREAM_SUB: var.queue_kms_master_key_id conditions -> DROPPED (BYO KMS not supported)
# UPSTREAM_SUB: var.ami_id_ssm_parameter_arns -> hardcoded ["arn:<partition>:ssm:<region>::parameter/aws/service/*"]
# UPSTREAM_SUB: var.iam_policy_statements dynamic block -> DROPPED
# ──────────────────────────────────────────

data "aws_iam_policy_document" "karpenter_controller_ec2" {
  statement {
    sid = "AllowScopedEC2InstanceAccessActions"
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}::image/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}::snapshot/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:security-group/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:subnet/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:capacity-reservation/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:placement-group/*"
    ]

    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet"
    ]
  }

  statement {
    sid = "AllowScopedEC2LaunchTemplateAccessActions"
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:launch-template/*"
    ]

    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${aws_eks_cluster.this.name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid = "AllowScopedEC2InstanceActionsWithTags"
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:fleet/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:volume/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:network-interface/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:launch-template/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:spot-instances-request/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:capacity-reservation/*"
    ]
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${aws_eks_cluster.this.name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [aws_eks_cluster.this.name]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid = "AllowScopedResourceCreationTagging"
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:fleet/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:volume/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:network-interface/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:launch-template/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:spot-instances-request/*",
    ]
    actions = ["ec2:CreateTags"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${aws_eks_cluster.this.name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [aws_eks_cluster.this.name]
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values = [
        "RunInstances",
        "CreateFleet",
        "CreateLaunchTemplate",
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedResourceTagging"
    resources = ["arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:instance/*"]
    actions   = ["ec2:CreateTags"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${aws_eks_cluster.this.name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }

    condition {
      test     = "StringEqualsIfExists"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [aws_eks_cluster.this.name]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values = [
        "eks:eks-cluster-name",
        "karpenter.sh/nodeclaim",
        "Name",
      ]
    }
  }

  statement {
    sid = "AllowScopedDeletion"
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:launch-template/*"
    ]

    actions = [
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${aws_eks_cluster.this.name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowRegionalReadActions"
    resources = ["*"]
    actions = [
      "ec2:DescribeCapacityReservations",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "ec2:DescribePlacementGroups"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [data.aws_region.current.region]
    }
  }

  statement {
    sid       = "AllowSSMReadActions"
    resources = ["arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}::parameter/aws/service/*"]
    actions   = ["ssm:GetParameter"]
  }

  statement {
    sid       = "AllowPricingReadActions"
    resources = ["*"]
    actions   = ["pricing:GetProducts"]
  }

  statement {
    sid       = "AllowZonalShiftReadActions"
    resources = ["*"]
    actions   = ["arc-zonal-shift:GetManagedResource"]
    condition {
      test     = "StringEquals"
      variable = "arc-zonal-shift:ResourceIdentifier"
      values   = ["arn:${data.aws_partition.current.partition}:eks:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:cluster/${aws_eks_cluster.this.name}"]
    }
  }

  statement {
    sid       = "AllowInterruptionQueueActions"
    resources = [aws_sqs_queue.karpenter.arn]
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage"
    ]
  }
}

data "aws_iam_policy_document" "karpenter_controller_iam" {
  statement {
    sid       = "AllowPassingInstanceRole"
    resources = [aws_iam_role.karpenter_node.arn]
    actions   = ["iam:PassRole"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid       = "AllowScopedInstanceProfileCreationActions"
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"]
    actions   = ["iam:CreateInstanceProfile"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${aws_eks_cluster.this.name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [aws_eks_cluster.this.name]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/topology.kubernetes.io/region"
      values   = [data.aws_region.current.region]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedInstanceProfileTagActions"
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"]
    actions   = ["iam:TagInstanceProfile"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${aws_eks_cluster.this.name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"
      values   = [data.aws_region.current.region]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${aws_eks_cluster.this.name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [aws_eks_cluster.this.name]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/topology.kubernetes.io/region"
      values   = [data.aws_region.current.region]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedInstanceProfileActions"
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"]
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:DeleteInstanceProfile"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${aws_eks_cluster.this.name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"
      values   = [data.aws_region.current.region]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowInstanceProfileReadActions"
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"]
    actions   = ["iam:GetInstanceProfile"]
  }

  statement {
    sid       = "AllowUnscopedInstanceProfileListAction"
    resources = ["*"]
    actions   = ["iam:ListInstanceProfiles"]
  }

  statement {
    sid       = "AllowAPIServerEndpointDiscovery"
    resources = ["arn:${data.aws_partition.current.partition}:eks:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:cluster/${aws_eks_cluster.this.name}"]
    actions   = ["eks:DescribeCluster"]
  }
}

# ──────────────────────────────────────────
# Queue policy document (transcribed from upstream main.tf queue block)
# ──────────────────────────────────────────

data "aws_iam_policy_document" "karpenter_queue" {
  # UPSTREAM_SUB: aws_sqs_queue.this[0].arn -> aws_sqs_queue.karpenter.arn
  # UPSTREAM_SUB: var.queue_policy_statements dynamic block -> DROPPED (no extra statements supported)

  statement {
    sid       = "SqsWrite"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.karpenter.arn]

    principals {
      type = "Service"
      identifiers = [
        "events.amazonaws.com",
        "sqs.amazonaws.com",
      ]
    }
  }

  statement {
    sid    = "DenyHTTP"
    effect = "Deny"
    actions = [
      "sqs:*"
    ]
    resources = [aws_sqs_queue.karpenter.arn]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values = [
        "false"
      ]
    }
    principals {
      type = "*"
      identifiers = [
        "*"
      ]
    }
  }
}

# ──────────────────────────────────────────
# Karpenter controller IAM role (Pod Identity trust)
# ──────────────────────────────────────────

data "aws_iam_policy_document" "karpenter_controller_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole", "sts:TagSession"]
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = "${var.name}-karpenter-controller"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume_role.json

  tags = merge(var.tags, {
    Name = "${var.name}-karpenter-controller"
  })
}

resource "aws_iam_policy" "karpenter_controller_ec2" {
  name        = "${var.name}-karpenter-controller-ec2"
  description = "Karpenter controller EC2/SSM/SQS permissions for cluster ${aws_eks_cluster.this.name}"
  policy      = data.aws_iam_policy_document.karpenter_controller_ec2.json

  tags = merge(var.tags, {
    Name = "${var.name}-karpenter-controller-ec2"
  })
}

resource "aws_iam_policy" "karpenter_controller_iam" {
  name        = "${var.name}-karpenter-controller-iam"
  description = "Karpenter controller IAM/EKS permissions for cluster ${aws_eks_cluster.this.name}"
  policy      = data.aws_iam_policy_document.karpenter_controller_iam.json

  tags = merge(var.tags, {
    Name = "${var.name}-karpenter-controller-iam"
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_ec2" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller_ec2.arn
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_iam" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller_iam.arn
}

# ──────────────────────────────────────────
# Karpenter node IAM role + instance profile
# (Pod Identity association lives in main.tf per resource-family rule)
# ──────────────────────────────────────────

data "aws_iam_policy_document" "karpenter_node_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "karpenter_node" {
  name               = "${var.name}-karpenter-node"
  assume_role_policy = data.aws_iam_policy_document.karpenter_node_assume_role.json

  tags = merge(var.tags, {
    Name = "${var.name}-karpenter-node"
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Default-replace map: caller-supplied karpenter_node_additional_policies REPLACES the default map entirely.
# Map keys are identifiers; values are policy ARNs (may contain __AWS_PARTITION__ placeholder).
resource "aws_iam_role_policy_attachment" "karpenter_node_additional" {
  for_each = var.karpenter_node_additional_policies

  role       = aws_iam_role.karpenter_node.name
  policy_arn = replace(each.value, var.partition_placeholder, data.aws_partition.current.partition)
}

resource "aws_iam_instance_profile" "karpenter_node" {
  count = var.karpenter_create_instance_profile ? 1 : 0

  name = "${var.name}-karpenter"
  role = aws_iam_role.karpenter_node.name

  tags = merge(var.tags, {
    Name = "${var.name}-karpenter"
  })
}

# ──────────────────────────────────────────
# SQS interruption queue
# ──────────────────────────────────────────

resource "aws_sqs_queue" "karpenter" {
  name                      = "${var.name}-karpenter"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = merge(var.tags, {
    Name = "${var.name}-karpenter"
  })
}

resource "aws_sqs_queue_policy" "karpenter" {
  queue_url = aws_sqs_queue.karpenter.url
  policy    = data.aws_iam_policy_document.karpenter_queue.json
}

# ──────────────────────────────────────────
# EventBridge rules + targets (4 events → SQS)
# ──────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each = local.karpenter_events

  name_prefix   = "${var.name}-${each.value.name}-"
  description   = each.value.description
  event_pattern = jsonencode(each.value.event_pattern)

  tags = merge(var.tags, {
    Name        = "${var.name}-${each.value.name}"
    ClusterName = aws_eks_cluster.this.name
  })
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each = local.karpenter_events

  rule      = aws_cloudwatch_event_rule.karpenter[each.key].name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter.arn
}
