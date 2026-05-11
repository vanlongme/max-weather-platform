variable "name" {
  description = "Resource name prefix (typically local.master_prefix from composition, e.g. 'poc-max-weather'). Combined with function map key to produce resource names: <name>-<key>."
  type        = string
}

variable "tags" {
  description = "Common tags merged onto every resource."
  type        = map(string)
  default     = {}
}

variable "functions" {
  description = "Map of Lambda functions to deploy. Supplying this map REPLACES the default entirely (no merge). Each map key becomes part of the resource name: <name>-<key><function_name_suffix>."
  type = map(object({
    source_dir           = string
    handler              = string
    runtime              = optional(string, "nodejs22.x")
    memory_size          = optional(number, 128)
    timeout              = optional(number, 5)
    environment          = optional(map(string), {})
    log_retention_days   = optional(number, 14)
    function_name_suffix = optional(string, "")
    role_arn             = string
    invoke_principals    = optional(map(string), {})
    npm_install_dir      = optional(string, null)
  }))
  default = {}
}
