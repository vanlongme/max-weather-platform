locals {
  functions_with_npm = { for k, v in var.functions : k => v if v.npm_install_dir != null }
}
