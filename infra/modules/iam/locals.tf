locals {
  default_pod_identity_roles = {
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

  pod_identity_roles_effective = var.pod_identity_roles == null ? local.default_pod_identity_roles : var.pod_identity_roles

  irsa_roles_effective = (var.oidc_provider_arn == "" || var.oidc_provider_url == "") ? {} : var.irsa_roles
}
