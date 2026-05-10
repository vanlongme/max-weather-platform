output "vpc_id" {
  description = "VPC ID."
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.networking.public_subnet_ids
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint."
  value       = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider."
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "URL of the EKS OIDC provider (without https://)."
  value       = module.eks.oidc_provider_url
}

output "ecr_api_repository_url" {
  description = "ECR URL for the weather API image."
  value       = module.ecr.repository_urls["${local.master_prefix}-api"]
}

output "ecr_lambda_repository_url" {
  description = "ECR URL for the Lambda authorizer image."
  value       = module.ecr.repository_urls["${local.master_prefix}-lambda-authorizer"]
}

output "cognito_client_id" {
  description = "Cognito app client ID."
  value       = module.cognito.client_id
}

output "cognito_token_endpoint" {
  description = "Cognito OAuth2 token endpoint."
  value       = module.cognito.token_endpoint
}

output "cognito_jwks_uri" {
  description = "Cognito JWKS URI for JWT validation."
  value       = module.cognito.jwks_uri
}

output "eks_application_log_group" {
  description = "CloudWatch log group for application logs (consumed by Fluent Bit values.yaml)."
  value       = module.cloudwatch.eks_application_log_group
}

output "cluster_autoscaler_role_arn" {
  description = "Pod Identity role ARN for the cluster-autoscaler Helm chart (informational; the eks module creates the ServiceAccount binding via aws_eks_pod_identity_association)."
  value       = module.iam.cluster_autoscaler_role_arn
}

output "fluent_bit_role_arn" {
  description = "Pod Identity role ARN for the Fluent Bit DaemonSet (informational)."
  value       = module.iam.fluent_bit_role_arn
}

output "aws_lb_controller_role_arn" {
  description = "Pod Identity role ARN for the AWS Load Balancer Controller Helm chart (informational)."
  value       = module.iam.aws_lb_controller_role_arn
}

output "external_secrets_role_arn" {
  description = "Pod Identity role ARN for the External Secrets Operator Helm chart (informational)."
  value       = module.iam.external_secrets_role_arn
}

output "jenkins_role_arn" {
  description = "Pod Identity role ARN for Jenkins (informational; also used by the eks module access entry)."
  value       = module.iam.jenkins_role_arn
}

output "iam_service_role_arns" {
  description = "Map of AWS service-principal IAM role ARNs created via the iam module."
  value       = module.iam.service_role_arns
}

output "iam_irsa_role_arns" {
  description = "Map of legacy IRSA role ARNs created via the iam module."
  value       = module.iam.irsa_role_arns
}

output "karpenter_queue_name" {
  description = "SQS queue name for Karpenter EC2 interruption events (consumed by Karpenter Helm values)."
  value       = module.eks.karpenter_queue_name
}

output "karpenter_node_iam_role_name" {
  description = "IAM role name attached to nodes Karpenter provisions (referenced from EC2NodeClass)."
  value       = module.eks.karpenter_node_iam_role_name
}

output "karpenter_instance_profile_name" {
  description = "Instance profile name attached to nodes Karpenter provisions."
  value       = module.eks.karpenter_instance_profile_name
}
