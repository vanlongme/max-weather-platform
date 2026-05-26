resource "null_resource" "npm_install" {
  for_each = local.functions_with_npm

  triggers = {
    package_lock_hash = filemd5("${each.value.npm_install_dir}/package-lock.json")
  }

  provisioner "local-exec" {
    command     = "npm ci --omit=dev"
    working_dir = each.value.npm_install_dir
  }
}
