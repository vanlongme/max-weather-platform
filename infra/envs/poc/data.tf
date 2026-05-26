data "aws_caller_identity" "current" {}

data "aws_lb" "ingress_nlb" {
  tags = {
    "kubernetes.io/service-name" = "ingress-nginx/ingress-nginx-controller"
  }

  depends_on = [module.eks_self_managed_addons]
}

data "aws_lb_listener" "ingress_nlb_80" {
  load_balancer_arn = data.aws_lb.ingress_nlb.arn
  port              = 80
}
