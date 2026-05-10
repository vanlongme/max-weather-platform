locals {
  repositories_resolved = {
    for name, cfg in var.repositories : name => {
      image_tag_mutability       = coalesce(cfg.image_tag_mutability, var.image_tag_mutability)
      scan_on_push               = cfg.scan_on_push == null ? var.scan_on_push : cfg.scan_on_push
      keep_tagged_image_count    = coalesce(cfg.keep_tagged_image_count, var.keep_tagged_image_count)
      untagged_image_expiry_days = coalesce(cfg.untagged_image_expiry_days, var.untagged_image_expiry_days)
      tag_prefix_list            = cfg.tag_prefix_list
    }
  }
}

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
        rulePriority = 1
        description  = "Keep last ${local.repositories_resolved[each.key].keep_tagged_image_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = local.repositories_resolved[each.key].tag_prefix_list
          countType     = "imageCountMoreThan"
          countNumber   = local.repositories_resolved[each.key].keep_tagged_image_count
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after ${local.repositories_resolved[each.key].untagged_image_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = local.repositories_resolved[each.key].untagged_image_expiry_days
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}
