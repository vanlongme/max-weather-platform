###############################################################################
# IRSA roles
#
# Single for_each driven by var.irsa_roles (or local.default_irsa_roles when
# the variable is null). The default map ships:
#   - jenkins             (jenkins:jenkins)               — ECR push, EKS describe, Lambda deploy, CloudWatch Logs
#   - cluster-autoscaler  (kube-system:cluster-autoscaler)
#   - fluent-bit          (amazon-cloudwatch:fluent-bit)
#   - aws-lb-controller   (kube-system:aws-load-balancer-controller)
#   - external-secrets    (external-secrets:external-secrets)
#
# Two-phase apply: when var.oidc_provider_arn == "" (phase 1, before EKS exists),
# for_each evaluates to {} and no IRSA roles are created. Phase 2 sets the OIDC
# provider ARN/URL from the eks module outputs and all 5 roles are created.
#
# Policy templating: jenkins's LambdaDeployAccess Resource ARN uses
# __AWS_PARTITION__ / __AWS_REGION__ / __AWS_ACCOUNT_ID__ / __CLUSTER_NAME__
# placeholders that are substituted here. Defaults live in locals (not in the
# variable default) because Terraform forbids function calls — including
# jsonencode() — in variable defaults.
###############################################################################

locals {
  default_irsa_roles = {
    jenkins = {
      namespace        = "jenkins"
      service_account  = "jenkins"
      role_name_suffix = "jenkins"
      policy_json = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Sid    = "ECRAccess"
            Effect = "Allow"
            Action = [
              "ecr:GetAuthorizationToken",
              "ecr:BatchCheckLayerAvailability",
              "ecr:GetDownloadUrlForLayer",
              "ecr:BatchGetImage",
              "ecr:PutImage",
              "ecr:InitiateLayerUpload",
              "ecr:UploadLayerPart",
              "ecr:CompleteLayerUpload",
              "ecr:DescribeRepositories",
              "ecr:ListImages",
            ]
            Resource = "*"
          },
          {
            Sid    = "EKSAccess"
            Effect = "Allow"
            Action = [
              "eks:DescribeCluster",
              "eks:ListClusters",
            ]
            Resource = "*"
          },
          {
            Sid    = "LambdaDeployAccess"
            Effect = "Allow"
            Action = [
              "lambda:UpdateFunctionCode",
              "lambda:GetFunction",
            ]
            Resource = "arn:__AWS_PARTITION__:lambda:__AWS_REGION__:__AWS_ACCOUNT_ID__:function:__CLUSTER_NAME__-*"
          },
          {
            Sid    = "CloudWatchLogs"
            Effect = "Allow"
            Action = [
              "logs:CreateLogGroup",
              "logs:CreateLogStream",
              "logs:PutLogEvents",
              "logs:DescribeLogGroups",
            ]
            Resource = "*"
          },
        ]
      })
    }
    cluster-autoscaler = {
      namespace        = "kube-system"
      service_account  = "cluster-autoscaler"
      role_name_suffix = "cluster-autoscaler"
      policy_json = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "autoscaling:DescribeAutoScalingGroups",
              "autoscaling:DescribeAutoScalingInstances",
              "autoscaling:DescribeLaunchConfigurations",
              "autoscaling:DescribeScalingActivities",
              "autoscaling:DescribeTags",
              "ec2:DescribeInstanceTypes",
              "ec2:DescribeLaunchTemplateVersions",
              "ec2:DescribeImages",
              "ec2:GetInstanceTypesFromInstanceRequirements",
              "eks:DescribeNodegroup",
            ]
            Resource = "*"
          },
          {
            Effect = "Allow"
            Action = [
              "autoscaling:SetDesiredCapacity",
              "autoscaling:TerminateInstanceInAutoScalingGroup",
            ]
            Resource = "*"
          },
        ]
      })
    }
    fluent-bit = {
      namespace        = "amazon-cloudwatch"
      service_account  = "fluent-bit"
      role_name_suffix = "fluent-bit"
      policy_json = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "logs:CreateLogGroup",
              "logs:CreateLogStream",
              "logs:PutLogEvents",
              "logs:DescribeLogGroups",
              "logs:DescribeLogStreams",
              "logs:PutRetentionPolicy",
            ]
            Resource = "*"
          },
        ]
      })
    }
    aws-lb-controller = {
      namespace        = "kube-system"
      service_account  = "aws-load-balancer-controller"
      role_name_suffix = "aws-lb-controller"
      policy_json = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect   = "Allow"
            Action   = ["iam:CreateServiceLinkedRole"]
            Resource = "*"
            Condition = {
              StringEquals = {
                "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
              }
            }
          },
          {
            Effect = "Allow"
            Action = [
              "ec2:DescribeAccountAttributes",
              "ec2:DescribeAddresses",
              "ec2:DescribeAvailabilityZones",
              "ec2:DescribeInternetGateways",
              "ec2:DescribeVpcs",
              "ec2:DescribeVpcPeeringConnections",
              "ec2:DescribeSubnets",
              "ec2:DescribeSecurityGroups",
              "ec2:DescribeInstances",
              "ec2:DescribeNetworkInterfaces",
              "ec2:DescribeTags",
              "ec2:GetCoipPoolUsage",
              "ec2:DescribeCoipPools",
              "elasticloadbalancing:DescribeLoadBalancers",
              "elasticloadbalancing:DescribeLoadBalancerAttributes",
              "elasticloadbalancing:DescribeListeners",
              "elasticloadbalancing:DescribeListenerCertificates",
              "elasticloadbalancing:DescribeSSLPolicies",
              "elasticloadbalancing:DescribeRules",
              "elasticloadbalancing:DescribeTargetGroups",
              "elasticloadbalancing:DescribeTargetGroupAttributes",
              "elasticloadbalancing:DescribeTargetHealth",
              "elasticloadbalancing:DescribeTags",
            ]
            Resource = "*"
          },
          {
            Effect = "Allow"
            Action = [
              "elasticloadbalancing:CreateLoadBalancer",
              "elasticloadbalancing:CreateTargetGroup",
              "elasticloadbalancing:CreateListener",
              "elasticloadbalancing:DeleteListener",
              "elasticloadbalancing:CreateRule",
              "elasticloadbalancing:DeleteRule",
              "elasticloadbalancing:ModifyLoadBalancerAttributes",
              "elasticloadbalancing:SetIpAddressType",
              "elasticloadbalancing:SetSecurityGroups",
              "elasticloadbalancing:SetSubnets",
              "elasticloadbalancing:DeleteLoadBalancer",
              "elasticloadbalancing:ModifyTargetGroup",
              "elasticloadbalancing:ModifyTargetGroupAttributes",
              "elasticloadbalancing:DeleteTargetGroup",
              "elasticloadbalancing:RegisterTargets",
              "elasticloadbalancing:DeregisterTargets",
              "elasticloadbalancing:SetWebAcl",
              "elasticloadbalancing:ModifyListener",
              "elasticloadbalancing:AddListenerCertificates",
              "elasticloadbalancing:RemoveListenerCertificates",
              "elasticloadbalancing:ModifyRule",
              "elasticloadbalancing:AddTags",
              "elasticloadbalancing:RemoveTags",
            ]
            Resource = "*"
          },
        ]
      })
    }
    external-secrets = {
      namespace        = "external-secrets"
      service_account  = "external-secrets"
      role_name_suffix = "external-secrets"
      policy_json = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "secretsmanager:GetSecretValue",
              "secretsmanager:DescribeSecret",
              "secretsmanager:ListSecrets",
            ]
            Resource = "*"
          },
          {
            Effect = "Allow"
            Action = [
              "ssm:GetParameter",
              "ssm:GetParameters",
              "ssm:GetParametersByPath",
              "ssm:DescribeParameters",
            ]
            Resource = "*"
          },
        ]
      })
    }
  }

  irsa_roles = var.irsa_roles == null ? local.default_irsa_roles : var.irsa_roles

  irsa_roles_effective = var.oidc_provider_arn == "" ? {} : local.irsa_roles
}
