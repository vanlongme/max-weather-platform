data "archive_file" "function" {
  for_each = var.functions

  type        = "zip"
  source_dir  = each.value.source_dir
  output_path = "${path.module}/.terraform/archive/${each.key}.zip"

  depends_on = [null_resource.npm_install]
}
