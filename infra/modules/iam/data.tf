data "aws_partition" "current" {}

data "aws_iam_policy_document" "service_assume_role" {
  for_each = var.service_roles

  statement {
    effect  = var.service_role_assume_effect
    actions = var.service_role_assume_actions
    principals {
      type        = var.service_role_assume_principal_type
      identifiers = each.value.service_principals
    }
  }
}

data "aws_iam_policy_document" "irsa_assume_role" {
  for_each = local.irsa_roles_effective

  statement {
    effect  = var.irsa_assume_role_effect
    actions = [var.irsa_assume_role_action]
    principals {
      type        = var.irsa_assume_role_principal_type
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = var.irsa_assume_role_condition_test
      variable = "${var.oidc_provider_url}${var.irsa_assume_role_sub_suffix}"
      values   = ["${var.irsa_assume_role_subject_prefix}${each.value.namespace}:${each.value.service_account}"]
    }
    condition {
      test     = var.irsa_assume_role_condition_test
      variable = "${var.oidc_provider_url}${var.irsa_assume_role_aud_suffix}"
      values   = [var.irsa_assume_role_audience]
    }
  }
}

data "aws_iam_policy_document" "pod_identity_assume_role" {
  statement {
    effect  = var.pod_identity_assume_role_effect
    actions = var.pod_identity_assume_role_actions
    principals {
      type        = var.pod_identity_assume_role_principal_type
      identifiers = [var.pod_identity_assume_role_principal_service]
    }
  }
}
