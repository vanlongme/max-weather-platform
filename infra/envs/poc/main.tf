module "cloudwatch" {
  source = "../../modules/cloudwatch"

  name               = local.master_prefix
  log_retention_days = var.log_retention_days
  log_groups         = var.log_groups
  tags               = local.common_tags
}

module "networking" {
  source = "../../modules/networking"

  name                = local.master_prefix
  eks_cluster_name    = "${local.master_prefix}-cluster"
  vpc_cidr            = var.vpc_cidr
  availability_zones  = var.availability_zones
  public_subnet_cidrs = var.public_subnet_cidrs
  tags                = local.common_tags
}

module "ecr" {
  source = "../../modules/ecr"

  name         = local.master_prefix
  repositories = var.ecr_repositories
  tags         = local.common_tags
}

module "secrets" {
  source = "../../modules/secrets"

  name    = local.master_prefix
  secrets = var.secrets
  tags    = local.common_tags
}

module "lambda" {
  source = "../../modules/lambda"

  name = local.master_prefix
  tags = local.common_tags

  functions = length(var.lambda_functions) > 0 ? var.lambda_functions : {
    authorizer = {
      source_dir      = "${path.module}/lambdas/authorizer"
      handler         = "src/index.handler"
      runtime         = "nodejs22.x"
      memory_size     = 128
      timeout         = 5
      role_arn        = module.iam.lambda_authorizer_role_arn
      npm_install_dir = "${path.module}/lambdas/authorizer"
      environment = {
        AUTHORIZER_SECRET_ARN = module.secrets.authorizer_jwt_secret_arn
        REQUIRED_SCOPE        = "weather-api/read"
        JWT_ISSUER            = "max-weather-authorizer"
      }
      invoke_principals = {
        api-gateway = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      }
    }
  }

  depends_on = [module.iam, module.secrets]
}

module "iam" {
  source = "../../modules/iam"

  name               = local.master_prefix
  aws_region         = var.aws_region
  aws_account_id     = data.aws_caller_identity.current.account_id
  service_roles      = var.iam_service_roles
  irsa_roles         = var.iam_irsa_roles
  pod_identity_roles = var.pod_identity_roles
  tags               = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  name                   = local.master_prefix
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
  pod_identity_associations       = module.iam.pod_identity_role_bindings

  tags = local.common_tags

  depends_on = [module.cloudwatch, module.networking]
}

module "eks_self_managed_addons" {
  source = "./eks-self-managed-addons"

  cluster_name                       = module.eks.cluster_name
  cluster_endpoint                   = module.eks.cluster_endpoint
  cluster_certificate_authority_data = module.eks.cluster_ca_data
  aws_region                         = var.aws_region
  vpc_id                             = module.networking.vpc_id
  log_group_name                     = module.cloudwatch.eks_application_log_group
  karpenter_queue_name               = module.eks.karpenter_queue_name
  karpenter_node_iam_role_name       = module.eks.karpenter_node_iam_role_name

  depends_on = [module.eks, module.cloudwatch]
}
