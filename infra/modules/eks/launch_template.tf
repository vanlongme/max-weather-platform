# launch_template.tf - per managed node group launch template.
# Module owns the LT (rather than letting EKS auto-manage) so callers can
# configure block_device_mappings (volume_type, iops, throughput, device_name)
# beyond what the native aws_eks_node_group.disk_size arg supports.

resource "aws_launch_template" "node" {
  for_each = var.eks_managed_node_groups

  name        = "${var.name}${var.node_group_name_separator}${each.key}"
  description = "Launch template for EKS managed node group ${each.key}"

  # Attach dedicated node SG (NOT cluster primary SG). Required for pod-to-pod
  # traffic between MNG and Karpenter nodes (both use this SG via discovery tag).
  # AGENTS.md rule: "NEVER attach cluster primary SG to nodes — use dedicated
  # aws_security_group.node". When LT omits SG, EKS falls back to cluster primary
  # SG which blocks node-SG sourced traffic on app ports (e.g. 8080).
  vpc_security_group_ids = [aws_security_group.node.id]

  user_data = startswith(each.value.ami_type, "BOTTLEROCKET_") ? base64encode(coalesce(each.value.bottlerocket_user_data, local.default_bottlerocket_user_data)) : null

  monitoring {
    enabled = each.value.enable_monitoring
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  dynamic "block_device_mappings" {
    for_each = each.value.block_device_mappings
    content {
      device_name = block_device_mappings.value.device_name

      ebs {
        volume_size           = block_device_mappings.value.volume_size
        volume_type           = block_device_mappings.value.volume_type
        iops                  = block_device_mappings.value.iops
        throughput            = block_device_mappings.value.throughput
        encrypted             = block_device_mappings.value.encrypted
        delete_on_termination = block_device_mappings.value.delete_on_termination
        kms_key_id            = coalesce(block_device_mappings.value.kms_key_id, local.ebs_kms_key_arn)
      }
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, each.value.tags, {
      Name = "${local.cluster_name}-${each.key}"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, each.value.tags, {
      Name = "${local.cluster_name}-${each.key}"
    })
  }

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.name}${var.node_group_name_separator}${each.key}"
  })

  lifecycle {
    create_before_destroy = true
  }
}
