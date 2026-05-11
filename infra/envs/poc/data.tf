data "aws_caller_identity" "current" {}

data "aws_lb" "ingress_nlb" {
  tags = {
    "kubernetes.io/service-name" = "ingress-nginx/ingress-nginx-controller"
  }

  depends_on = [module.eks_self_managed_addons]
}
