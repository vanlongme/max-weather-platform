resource "aws_iam_role" "irsa" {
  for_each = local.irsa_roles_effective

  name               = "${var.cluster_name}-${coalesce(each.value.role_name_suffix, each.key)}"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume_role[each.key].json
  tags = merge(var.tags, {
    Name = "${var.cluster_name}-${coalesce(each.value.role_name_suffix, each.key)}"
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
    var.cluster_name_placeholder, var.cluster_name,
  )
}
