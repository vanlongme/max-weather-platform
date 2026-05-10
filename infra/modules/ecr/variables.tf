variable "repositories" {
  description = "Map of ECR repositories to create, keyed by repository name. Each value is an object with optional per-repo overrides; when an override is null the module-level default applies. The default map creates max-weather-api and max-weather-lambda-authorizer with module-level defaults."
  type = map(object({
    image_tag_mutability       = optional(string)
    scan_on_push               = optional(bool)
    keep_tagged_image_count    = optional(number)
    untagged_image_expiry_days = optional(number)
    tag_prefix_list            = optional(list(string), ["staging-", "prod-"])
  }))
  default = {
    "max-weather-api"               = {}
    "max-weather-lambda-authorizer" = {}
  }
}

variable "image_tag_mutability" {
  description = "Tag mutability setting for the repositories: MUTABLE or IMMUTABLE."
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Whether to enable image vulnerability scanning on push."
  type        = bool
  default     = true
}

variable "keep_tagged_image_count" {
  description = "Number of most-recent staging-/prod- tagged images to retain."
  type        = number
  default     = 10
}

variable "untagged_image_expiry_days" {
  description = "Number of days to keep untagged images before expiry."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Common tags to apply to all resources."
  type        = map(string)
  default     = {}
}
