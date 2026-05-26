resource "aws_security_group" "node" {
  name        = "${local.cluster_name}-node-sg"
  description = "Security group for EKS managed node group instances in cluster ${local.cluster_name}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name                                          = "${local.cluster_name}-node-sg"
    "karpenter.sh/discovery"                      = local.cluster_name
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  })
}

# Node SG ingress rules — fine-grained per AWS / terraform-aws-modules best practice.
# https://github.com/terraform-aws-modules/terraform-aws-eks
# Keys are stable; callers may extend via var.node_security_group_additional_rules.

resource "aws_vpc_security_group_ingress_rule" "node" {
  for_each = local.node_security_group_ingress_rules_all

  security_group_id            = aws_security_group.node.id
  description                  = each.value.description
  ip_protocol                  = each.value.ip_protocol
  from_port                    = lookup(each.value, "from_port", null)
  to_port                      = lookup(each.value, "to_port", null)
  referenced_security_group_id = lookup(each.value, "source", null) == "cluster" ? aws_eks_cluster.this.vpc_config[0].cluster_security_group_id : (lookup(each.value, "source", null) == "self" ? aws_security_group.node.id : null)
  cidr_ipv4                    = lookup(each.value, "cidr_ipv4", null)
}

resource "aws_vpc_security_group_egress_rule" "node" {
  for_each = local.node_security_group_egress_rules_all

  security_group_id            = aws_security_group.node.id
  description                  = each.value.description
  ip_protocol                  = each.value.ip_protocol
  from_port                    = lookup(each.value, "from_port", null)
  to_port                      = lookup(each.value, "to_port", null)
  cidr_ipv4                    = lookup(each.value, "cidr_ipv4", null)
  referenced_security_group_id = lookup(each.value, "referenced_security_group_id", null)
}

# Cluster SG ingress — allow nodes to reach the EKS API server (443) on the
# control-plane security group. AWS auto-creates 443-from-additional-SGs in
# some cases but never from the dedicated node SG when nodes are not bound to
# the cluster primary SG. We add it explicitly.

resource "aws_vpc_security_group_ingress_rule" "cluster_from_node" {
  security_group_id            = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description                  = "Nodes to cluster API (443)"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.node.id
}
