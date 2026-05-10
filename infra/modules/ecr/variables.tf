variable "name" {
  description = "Name prefix applied to every resource (typically the master_prefix from the composition, e.g. 'poc-max-weather'). Each repository's final name is <var.name>-<key>-repo."
  type        = string
}

variable "repositories" {
  description = "Map of ECR repositories to create, keyed by short name. Each value is an object with optional per-repo overrides; when an override is null the module-level default applies. Final repository name is <var.name>-<key>-repo (e.g. key 'api' with var.name 'poc-max-weather' produces 'poc-max-weather-api-repo'). The default map creates 'api' and 'base-nodejs' repositories. Note: the lambda-authorizer is deployed as a ZIP package via the lambda module — no ECR repo required."
  type = map(object({
    image_tag_mutability       = optional(string)
    scan_on_push               = optional(bool)
    keep_tagged_image_count    = optional(number)
    untagged_image_expiry_days = optional(number)
    tag_prefix_list            = optional(list(string), ["staging-", "prod-"])
  }))
  default = {
    api         = {}
    base-nodejs = {}
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

variable "lifecycle_keep_tagged_priority" {
  description = "rulePriority assigned to the lifecycle rule that retains the N most recent tagged images."
  type        = number
  default     = 1
}

variable "lifecycle_expire_untagged_priority" {
  description = "rulePriority assigned to the lifecycle rule that expires untagged images."
  type        = number
  default     = 2
}

variable "lifecycle_keep_tagged_description_template" {
  description = "Description template for the keep-tagged lifecycle rule. The placeholder var.lifecycle_count_placeholder is substituted with the per-repository keep_tagged_image_count."
  type        = string
  default     = "Keep last __COUNT__ tagged images"
}

variable "lifecycle_expire_untagged_description_template" {
  description = "Description template for the expire-untagged lifecycle rule. The placeholder var.lifecycle_count_placeholder is substituted with the per-repository untagged_image_expiry_days."
  type        = string
  default     = "Expire untagged images after __COUNT__ days"
}

variable "lifecycle_count_placeholder" {
  description = "Literal placeholder substituted in lifecycle rule descriptions with the per-repository numeric value."
  type        = string
  default     = "__COUNT__"
}

variable "lifecycle_tag_status_tagged" {
  description = "tagStatus value used by the keep-tagged lifecycle rule."
  type        = string
  default     = "tagged"
}

variable "lifecycle_tag_status_untagged" {
  description = "tagStatus value used by the expire-untagged lifecycle rule."
  type        = string
  default     = "untagged"
}

variable "lifecycle_count_type_more_than" {
  description = "countType used to express 'retain at most N images'."
  type        = string
  default     = "imageCountMoreThan"
}

variable "lifecycle_count_type_since_pushed" {
  description = "countType used to express 'expire images older than N units'."
  type        = string
  default     = "sinceImagePushed"
}

variable "lifecycle_count_unit" {
  description = "countUnit used by the expire-untagged lifecycle rule."
  type        = string
  default     = "days"
}

variable "lifecycle_action_type" {
  description = "Action type for ECR lifecycle rules."
  type        = string
  default     = "expire"
}
