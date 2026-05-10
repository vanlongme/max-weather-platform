resource "aws_iam_role" "service" {
  for_each = var.service_roles

  name               = "${var.name}-${coalesce(each.value.role_name_suffix, each.key)}${var.role_name_suffix}"
  assume_role_policy = data.aws_iam_policy_document.service_assume_role[each.key].json
  tags = merge(var.tags, {
    Name = "${var.name}-${coalesce(each.value.role_name_suffix, each.key)}${var.role_name_suffix}"
  })
}

resource "aws_iam_role_policy" "service" {
  for_each = { for k, v in var.service_roles : k => v if v.policy_json != null }

  name = "${each.key}${var.inline_policy_name_suffix}"
  role = aws_iam_role.service[each.key].id
  policy = replace(
    replace(
      replace(
        replace(each.value.policy_json, var.partition_placeholder, data.aws_partition.current.partition),
        var.region_placeholder, var.aws_region,
      ),
      var.account_id_placeholder, var.aws_account_id,
    ),
    var.cluster_name_placeholder, var.name,
  )
}

resource "aws_iam_role_policy_attachment" "service" {
  for_each = merge([
    for k, v in var.service_roles : {
      for arn in v.managed_policy_arns : "${k}|${arn}" => {
        role = k
        arn  = replace(arn, var.partition_placeholder, data.aws_partition.current.partition)
      }
    }
  ]...)

  role       = aws_iam_role.service[each.value.role].name
  policy_arn = each.value.arn
}

resource "aws_iam_role" "irsa" {
  for_each = local.irsa_roles_effective

  name               = "${var.name}-${coalesce(each.value.role_name_suffix, each.key)}${var.role_name_suffix}"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume_role[each.key].json
  tags = merge(var.tags, {
    Name = "${var.name}-${coalesce(each.value.role_name_suffix, each.key)}${var.role_name_suffix}"
  })
}

resource "aws_iam_role_policy" "irsa" {
  for_each = local.irsa_roles_effective

  name = "${each.key}${var.inline_policy_name_suffix}"
  role = aws_iam_role.irsa[each.key].id
  policy = replace(
    replace(
      replace(
        replace(each.value.policy_json, var.partition_placeholder, data.aws_partition.current.partition),
        var.region_placeholder, var.aws_region,
      ),
      var.account_id_placeholder, var.aws_account_id,
    ),
    var.cluster_name_placeholder, var.name,
  )
}

resource "aws_iam_role" "pod_identity" {
  for_each = local.pod_identity_roles_effective

  name               = "${var.name}-${coalesce(each.value.role_name_suffix, each.key)}${var.role_name_suffix}"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
  tags = merge(var.tags, {
    Name = "${var.name}-${coalesce(each.value.role_name_suffix, each.key)}${var.role_name_suffix}"
  })
}

resource "aws_iam_role_policy" "pod_identity" {
  for_each = local.pod_identity_roles_effective

  name = "${each.key}${var.inline_policy_name_suffix}"
  role = aws_iam_role.pod_identity[each.key].id
  policy = replace(
    replace(
      replace(
        replace(each.value.policy_json, var.partition_placeholder, data.aws_partition.current.partition),
        var.region_placeholder, var.aws_region,
      ),
      var.account_id_placeholder, var.aws_account_id,
    ),
    var.cluster_name_placeholder, var.name,
  )
}
