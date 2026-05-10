variable "repositories" {
  description = "List of ECR repository names to create."
  type        = list(string)
  default     = ["max-weather-api", "max-weather-lambda-authorizer"]
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
