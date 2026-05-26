resource "kubectl_manifest" "eniconfig" {
  for_each = var.enable_vpc_cni_custom_networking ? var.pod_subnet_ids_by_az : {}

  yaml_body = yamlencode({
    apiVersion = "crd.k8s.amazonaws.com/v1alpha1"
    kind       = "ENIConfig"
    metadata = {
      name = each.key
    }
    spec = {
      securityGroups = [aws_security_group.node.id]
      subnet         = each.value
    }
  })

  # Ordering: VPC CNI addon installs first (carries custom-networking env vars),
  # ENIConfig CRs apply next, node groups come up last (depends_on below in
  # aws_eks_node_group). This ensures the first node's kubelet sees a matching
  # ENIConfig for its AZ on registration and allocates pod ENIs from the
  # secondary CIDR — equivalent to the upstream module's `before_compute = true`
  # on the vpc-cni addon.
  #
  # Destroy ordering: depend on the caller-composed access entries so Terraform
  # tears down ENIConfig CRs BEFORE removing the principals that grant the
  # kubectl provider its cluster credentials. Without this, destroy fails with
  # "the server has asked for the client to provide credentials" because the
  # `data.aws_eks_cluster_auth` token loses its access entry mid-destroy and
  # the kubectl refresh/delete of eniconfig 401s.
  depends_on = [
    aws_eks_addon.this,
    aws_eks_access_entry.this,
    aws_eks_access_policy_association.this,
  ]
}
