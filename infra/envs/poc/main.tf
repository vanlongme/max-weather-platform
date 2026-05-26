module "cloudwatch" {
  source = "../../modules/cloudwatch"

  name               = local.master_prefix
  log_retention_days = var.log_retention_days
  log_groups         = var.log_groups
  tags               = local.common_tags
}

module "networking" {
  source = "../../modules/networking"

  name                             = local.master_prefix
  eks_cluster_name                 = "${local.master_prefix}-cluster"
  vpc_cidr                         = var.vpc_cidr
  availability_zones               = var.availability_zones
  public_subnet_cidrs              = var.public_subnet_cidrs
  private_subnet_cidrs             = var.private_subnet_cidrs
  enable_nat_gateway               = var.enable_nat_gateway
  enable_vpc_endpoints             = var.enable_vpc_endpoints
  vpc_interface_endpoints          = var.vpc_interface_endpoints
  enable_s3_gateway_endpoint       = var.enable_s3_gateway_endpoint
  vpc_endpoint_private_dns_enabled = var.vpc_endpoint_private_dns_enabled
  tags                             = local.common_tags
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
        STAGING_SECRET_ARN    = module.secrets.secret_arns["authorizer_jwt_secret"]
        PROD_SECRET_ARN       = module.secrets.secret_arns["authorizer_jwt_secret_prod"]
        STAGING_ISSUER        = "max-weather-staging"
        PROD_ISSUER           = "max-weather-prod"
        STAGING_SCOPE         = "weather:read"
        PROD_SCOPE            = "weather:read"
        AUTHORIZER_SECRET_ARN = module.secrets.secret_arns["authorizer_jwt_secret"]
        JWT_ISSUER            = "max-weather-authorizer"
        REQUIRED_SCOPE        = "weather:read"
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

  name            = local.master_prefix
  cluster_version = var.eks_cluster_version
  vpc_id          = module.networking.vpc_id
  subnet_ids      = module.networking.private_subnet_ids

  allowed_cidrs           = var.allowed_cidrs
  endpoint_private_access = var.endpoint_private_access
  endpoint_public_access  = var.endpoint_public_access
  enabled_log_types       = var.enabled_log_types

  eks_managed_node_groups         = local.eks_managed_node_groups_with_subnets
  eks_managed_node_group_defaults = var.eks_managed_node_group_defaults
  cluster_addons                  = var.cluster_addons
  access_entries                  = local.eks_access_entries_effective
  pod_identity_associations       = module.iam.pod_identity_role_bindings

  tags = local.common_tags
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
  private_subnet_ids                 = module.networking.private_subnet_ids

  depends_on = [module.eks, module.cloudwatch]
}

resource "aws_security_group" "apigw_vpclink" {
  name        = "${local.master_prefix}-apigw-vpclink-sg"
  description = "API Gateway VPC Link ENIs - egress to internal NLB targets."
  vpc_id      = module.networking.vpc_id

  egress {
    description = "Egress to NLB targets within the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, {
    Name = "${local.master_prefix}-apigw-vpclink-sg"
  })
}

module "api_gateway" {
  source = "../../modules/api_gateway"

  name                  = local.master_prefix
  lambda_authorizer_arn = module.lambda.function_arns["authorizer"]
  lambda_function_name  = module.lambda.function_names["authorizer"]
  nlb_dns               = data.aws_lb.ingress_nlb.dns_name
  ingress_host          = "staging.max-weather.local"
  tags                  = local.common_tags

  vpc_link_subnet_ids         = module.networking.private_subnet_ids
  vpc_link_security_group_ids = [aws_security_group.apigw_vpclink.id]
  nlb_listener_arn            = data.aws_lb_listener.ingress_nlb_80.arn

  stages = {
    staging = {
      secret_arn = module.secrets.secret_arns["authorizer_jwt_secret"]
      issuer     = "max-weather-staging"
      scope      = "weather:read"
    }
    prod = {
      secret_arn = module.secrets.secret_arns["authorizer_jwt_secret_prod"]
      issuer     = "max-weather-prod"
      scope      = "weather:read"
    }
  }

  depends_on = [module.lambda, module.secrets, module.eks_self_managed_addons]
}
