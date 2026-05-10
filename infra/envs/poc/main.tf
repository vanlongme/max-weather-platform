data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Project     = "max-weather"
    Environment = "poc"
    ManagedBy   = "terraform"
  }
}

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  cluster_name       = var.cluster_name
  log_retention_days = var.log_retention_days
  log_groups         = var.log_groups
  tags               = local.common_tags
}

module "networking" {
  source = "../../modules/networking"

  cluster_name        = var.cluster_name
  vpc_cidr            = var.vpc_cidr
  availability_zones  = var.availability_zones
  public_subnet_cidrs = var.public_subnet_cidrs
  tags                = local.common_tags
}

module "ecr" {
  source = "../../modules/ecr"

  repositories = var.ecr_repositories
  tags         = local.common_tags
}

module "cognito" {
  source = "../../modules/cognito"

  cluster_name  = var.cluster_name
  domain_prefix = var.cognito_domain_prefix
  app_clients   = var.cognito_app_clients
  tags          = local.common_tags
}

module "secrets" {
  source = "../../modules/secrets"

  cluster_name = var.cluster_name
  secrets      = var.secrets
  tags         = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name           = var.cluster_name
  cluster_version        = var.eks_cluster_version
  vpc_id                 = module.networking.vpc_id
  subnet_ids             = module.networking.public_subnet_ids
  allowed_cidrs          = var.allowed_cidrs
  operator_principal_arn = data.aws_caller_identity.current.arn
  jenkins_role_arn       = module.iam.jenkins_role_arn

  eks_managed_node_groups         = var.eks_managed_node_groups
  eks_managed_node_group_defaults = var.eks_managed_node_group_defaults
  cluster_addons                  = var.cluster_addons
  access_entries                  = var.eks_access_entries

  tags = local.common_tags

  depends_on = [module.cloudwatch, module.networking]
}

module "iam" {
  source = "../../modules/iam"

  cluster_name      = var.cluster_name
  aws_region        = var.aws_region
  aws_account_id    = data.aws_caller_identity.current.account_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  irsa_roles        = var.irsa_roles
  tags              = local.common_tags
}
