locals {
  common_tags = {
    Project     = var.cluster_name
    Environment = "poc"
    ManagedBy   = "terraform"
  }
}
