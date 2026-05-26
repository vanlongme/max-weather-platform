# kms resources for the EKS module.
#
# Bring-your-own (BYO) opt-in:
#   - var.existing_cluster_kms_key_arn = ARN  -> skip aws_kms_key.cluster + alias, use the supplied ARN.
#   - var.existing_ebs_kms_key_arn     = ARN  -> skip aws_kms_key.ebs + alias + policy doc, use the supplied ARN.
# Both default to null, preserving module-managed key creation.

resource "aws_kms_key" "cluster" {
  count = var.existing_cluster_kms_key_arn == null ? 1 : 0

  description             = "EKS cluster envelope encryption key for ${local.cluster_name}"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = var.kms_enable_key_rotation

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-cluster-key"
  })
}

resource "aws_kms_alias" "cluster" {
  count = var.existing_cluster_kms_key_arn == null ? 1 : 0

  name          = "alias/${local.cluster_name}-eks"
  target_key_id = aws_kms_key.cluster[0].key_id
}

resource "aws_kms_key" "ebs" {
  count = var.existing_ebs_kms_key_arn == null ? 1 : 0

  description             = "EKS node EBS volume encryption key for ${local.cluster_name}"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = var.kms_enable_key_rotation

  policy = data.aws_iam_policy_document.ebs_kms[0].json

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-ebs-key"
  })
}

resource "aws_kms_alias" "ebs" {
  count = var.existing_ebs_kms_key_arn == null ? 1 : 0

  name          = "alias/${local.cluster_name}-eks-ebs"
  target_key_id = aws_kms_key.ebs[0].key_id
}

data "aws_iam_policy_document" "ebs_kms" {
  count = var.existing_ebs_kms_key_arn == null ? 1 : 0

  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Encrypt + ReEncrypt* required for EBS volume creation (snapshot copy paths).
  statement {
    sid    = "AllowNodeRoles"
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [
        aws_iam_role.node.arn,
        aws_iam_role.karpenter_node.arn,
      ]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }

  # ASG service-linked role grant attachment — required so ASG can grant EC2
  # access to decrypt EBS volumes on instance launch. The `Service` principal
  # `autoscaling.amazonaws.com` is a no-op for the SLR; must use the explicit
  # SLR ARN. CreateGrant is gated by kms:GrantIsForAWSResource = true so the
  # SLR can only forward access, not use the key directly.
  # See: https://docs.aws.amazon.com/autoscaling/ec2/userguide/key-policy-requirements-EBS-encryption.html
  statement {
    sid    = "AllowAutoscalingSLRUse"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowAutoscalingSLRGrant"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }
    actions   = ["kms:CreateGrant"]
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}
