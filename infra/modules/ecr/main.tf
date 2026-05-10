resource "aws_ecr_repository" "repos" {
  for_each = local.repositories_resolved

  name                 = each.key
  image_tag_mutability = each.value.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = each.value.scan_on_push
  }

  tags = merge(var.tags, { Name = each.key })
}

resource "aws_ecr_lifecycle_policy" "repos" {
  for_each = aws_ecr_repository.repos

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = var.lifecycle_keep_tagged_priority
        description = replace(
          var.lifecycle_keep_tagged_description_template,
          var.lifecycle_count_placeholder,
          tostring(local.repositories_resolved[each.key].keep_tagged_image_count),
        )
        selection = {
          tagStatus     = var.lifecycle_tag_status_tagged
          tagPrefixList = local.repositories_resolved[each.key].tag_prefix_list
          countType     = var.lifecycle_count_type_more_than
          countNumber   = local.repositories_resolved[each.key].keep_tagged_image_count
        }
        action = {
          type = var.lifecycle_action_type
        }
      },
      {
        rulePriority = var.lifecycle_expire_untagged_priority
        description = replace(
          var.lifecycle_expire_untagged_description_template,
          var.lifecycle_count_placeholder,
          tostring(local.repositories_resolved[each.key].untagged_image_expiry_days),
        )
        selection = {
          tagStatus   = var.lifecycle_tag_status_untagged
          countType   = var.lifecycle_count_type_since_pushed
          countUnit   = var.lifecycle_count_unit
          countNumber = local.repositories_resolved[each.key].untagged_image_expiry_days
        }
        action = {
          type = var.lifecycle_action_type
        }
      },
    ]
  })
}
