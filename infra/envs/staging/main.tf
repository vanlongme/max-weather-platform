data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Project     = "max-weather"
    Environment = "staging"
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

  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = true
  tags                 = local.common_tags
}

module "iam" {
  source = "../../modules/iam"

  cluster_name      = var.cluster_name
  aws_region        = var.aws_region
  aws_account_id    = data.aws_caller_identity.current.account_id
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider_url = var.oidc_provider_url
  tags              = local.common_tags
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

module "eks_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name           = var.cluster_name
  cluster_version        = var.eks_cluster_version
  cluster_role_arn       = module.iam.eks_cluster_role_arn
  subnet_ids             = concat(module.networking.public_subnet_ids, module.networking.private_subnet_ids)
  allowed_cidrs          = var.allowed_cidrs
  operator_principal_arn = data.aws_caller_identity.current.arn
  jenkins_role_arn       = module.iam.jenkins_role_arn
  tags                   = local.common_tags

  depends_on = [module.cloudwatch, module.networking, module.iam]
}

module "eks_nodegroup" {
  source = "../../modules/eks-nodegroup"

  cluster_name       = module.eks_cluster.cluster_name
  node_role_arn      = module.iam.eks_node_role_arn
  private_subnet_ids = module.networking.private_subnet_ids
  min_size           = var.node_min_size
  max_size           = var.node_max_size
  desired_size       = var.node_desired_size
  tags               = local.common_tags

  depends_on = [module.eks_cluster]
}

module "namespaces" {
  source = "../../modules/namespaces"

  cluster_name = var.cluster_name

  depends_on = [module.eks_nodegroup]
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
