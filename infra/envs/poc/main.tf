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

  repositories = ["${var.cluster_name}-api", "${var.cluster_name}-lambda-authorizer"]
  tags         = local.common_tags
}

module "cognito" {
  source = "../../modules/cognito"

  cluster_name  = var.cluster_name
  domain_prefix = var.cognito_domain_prefix
  tags          = local.common_tags
}

module "secrets" {
  source = "../../modules/secrets"

  cluster_name = var.cluster_name
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
  node_instance_types    = var.node_instance_types
  node_min_size          = var.node_min_size
  node_max_size          = var.node_max_size
  node_desired_size      = var.node_desired_size
  tags                   = local.common_tags

  depends_on = [module.cloudwatch, module.networking]
}

module "iam" {
  source = "../../modules/iam"

  cluster_name      = var.cluster_name
  aws_region        = var.aws_region
  aws_account_id    = data.aws_caller_identity.current.account_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  tags              = local.common_tags
}

module "namespaces" {
  source = "../../modules/namespaces"

  cluster_name = var.cluster_name

  depends_on = [module.eks]
}

module "jenkins" {
  source = "../../modules/jenkins"

  vpc_id                = module.networking.vpc_id
  public_subnet_id      = module.networking.public_subnet_ids[0]
  instance_profile_name = module.iam.jenkins_instance_profile_name
  key_name              = var.jenkins_key_name
  allowed_cidrs         = var.allowed_cidrs
  tags                  = local.common_tags

  depends_on = [module.networking, module.iam]
}
