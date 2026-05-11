locals {
  repositories_resolved = {
    for key, cfg in var.repositories : "${var.name}-${key}-repo" => {
      image_tag_mutability       = coalesce(cfg.image_tag_mutability, var.image_tag_mutability)
      scan_on_push               = cfg.scan_on_push == null ? var.scan_on_push : cfg.scan_on_push
      keep_tagged_image_count    = coalesce(cfg.keep_tagged_image_count, var.keep_tagged_image_count)
      untagged_image_expiry_days = coalesce(cfg.untagged_image_expiry_days, var.untagged_image_expiry_days)
      tag_prefix_list            = cfg.tag_prefix_list
    }
  }
}
