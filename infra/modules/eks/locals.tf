locals {
  cluster_name = "${var.name}${var.cluster_name_suffix}"

  # KMS BYO: prefer caller-supplied ARN, fall back to module-created key.
  cluster_kms_key_arn = coalesce(
    var.existing_cluster_kms_key_arn,
    try(aws_kms_key.cluster[0].arn, null),
  )
  ebs_kms_key_arn = coalesce(
    var.existing_ebs_kms_key_arn,
    try(aws_kms_key.ebs[0].arn, null),
  )

  # VPC CNI custom networking env vars merged into the vpc-cni addon's
  # configuration_values when var.enable_vpc_cni_custom_networking = true.
  # Deep-merged with any existing env block in the addon entry so caller-set
  # tolerations / other keys (e.g. infra-node toleration) are preserved.
  vpc_cni_custom_networking_env = {
    AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"
    ENI_CONFIG_LABEL_DEF               = "topology.kubernetes.io/zone"
  }

  vpc_cni_entry_existing_config = try(
    jsondecode(var.cluster_addons["vpc-cni"].configuration_values),
    {},
  )

  vpc_cni_entry_merged_config = merge(
    local.vpc_cni_entry_existing_config,
    {
      env = merge(
        try(local.vpc_cni_entry_existing_config.env, {}),
        local.vpc_cni_custom_networking_env,
      )
    },
  )

  cluster_addons_effective = {
    for k, v in var.cluster_addons : k => (
      k == "vpc-cni" && var.enable_vpc_cni_custom_networking
      ? merge(v, { configuration_values = jsonencode(local.vpc_cni_entry_merged_config) })
      : v
    )
  }

  # Bottlerocket TOML applied (base64-encoded) to managed NG launch_template
  # user_data when ami_type matches BOTTLEROCKET_* and per-group override is null.
  # NEVER set settings.kubernetes.{cluster-name, api-server, cluster-certificate,
  # cluster-dns-ip, kube-reserved} — pluto/schnauzer auto-derive from EKS-injected
  # metadata at first boot; overriding breaks bootstrap. Bottlerocket factory
  # defaults (kernel.lockdown=integrity, settings.updates.*-base-url, image-gc
  # 85/80) intentionally omitted — adds stale-pin risk for no gain. Per-group
  # `bottlerocket_user_data` REPLACES this baseline.
  default_bottlerocket_user_data = <<-TOML
    [settings.host-containers.admin]
    enabled = false

    [settings.host-containers.control]
    enabled = true

    [settings.kubernetes]
    container-log-max-size = "25Mi"
    container-log-max-files = 5
    registry-qps = 10
    registry-burst = 20
    pod-pids-limit = 1024

    [settings.kubernetes.eviction-hard]
    "memory.available" = "200Mi"
    "nodefs.available" = "10%"

    [settings.kernel.sysctl]
    "net.core.somaxconn" = "4096"
    "net.ipv4.tcp_max_syn_backlog" = "1024"
    "fs.inotify.max_user_instances" = "8192"
    "fs.inotify.max_user_watches" = "524288"
    "vm.max_map_count" = "262144"
  TOML
}

locals {
  karpenter_events = {
    health_event = {
      name        = "HealthEvent"
      description = "Karpenter interrupt - AWS health event"
      event_pattern = {
        source      = ["aws.health"]
        detail-type = ["AWS Health Event"]
      }
    }
    spot_interruption = {
      name        = "SpotInterrupt"
      description = "Karpenter interrupt - EC2 spot instance interruption warning"
      event_pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Spot Instance Interruption Warning"]
      }
    }
    rebalance = {
      name        = "InstanceRebalance"
      description = "Karpenter interrupt - EC2 instance rebalance recommendation"
      event_pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance Rebalance Recommendation"]
      }
    }
    instance_state_change = {
      name        = "InstanceStateChange"
      description = "Karpenter interrupt - EC2 instance state-change notification"
      event_pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance State-change Notification"]
      }
    }
  }
}

locals {
  # Fine-grained node SG rules — canonical set from terraform-aws-modules/eks
  # node_groups.tf (cluster→node mgmt ports + intra-node DNS/ephemeral).
  # source = "cluster" → primary cluster SG; "self" → node SG; else cidr_ipv4.
  node_security_group_ingress_rules_default = {
    cluster_api_to_node = {
      description = "Cluster API to node 443"
      source      = "cluster"
      ip_protocol = "tcp"
      from_port   = 443
      to_port     = 443
    }
    cluster_kubelet = {
      description = "Cluster API to node kubelet 10250"
      source      = "cluster"
      ip_protocol = "tcp"
      from_port   = 10250
      to_port     = 10250
    }
    cluster_webhook_4443 = {
      description = "Cluster API to webhook 4443 (metrics-server/prometheus-adapter)"
      source      = "cluster"
      ip_protocol = "tcp"
      from_port   = 4443
      to_port     = 4443
    }
    cluster_webhook_6443 = {
      description = "Cluster API to webhook 6443"
      source      = "cluster"
      ip_protocol = "tcp"
      from_port   = 6443
      to_port     = 6443
    }
    cluster_webhook_8443 = {
      description = "Cluster API to webhook 8443 (karpenter/aws-lb-controller)"
      source      = "cluster"
      ip_protocol = "tcp"
      from_port   = 8443
      to_port     = 8443
    }
    cluster_webhook_9443 = {
      description = "Cluster API to webhook 9443 (kube-prometheus-stack)"
      source      = "cluster"
      ip_protocol = "tcp"
      from_port   = 9443
      to_port     = 9443
    }
    self_coredns_tcp = {
      description = "Node-to-node CoreDNS 53/tcp"
      source      = "self"
      ip_protocol = "tcp"
      from_port   = 53
      to_port     = 53
    }
    self_coredns_udp = {
      description = "Node-to-node CoreDNS 53/udp"
      source      = "self"
      ip_protocol = "udp"
      from_port   = 53
      to_port     = 53
    }
    self_ephemeral = {
      description = "Node-to-node ephemeral 1025-65535"
      source      = "self"
      ip_protocol = "tcp"
      from_port   = 1025
      to_port     = 65535
    }
  }

  node_security_group_egress_rules_default = {
    all_egress = {
      description = "Node all egress (private cluster reaches AWS APIs via VPC endpoints)"
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  # REPLACE semantics — caller-supplied ingress/egress map replaces default entirely.
  node_security_group_ingress_rules_all = coalesce(
    var.node_security_group_additional_rules.ingress,
    local.node_security_group_ingress_rules_default,
  )
  node_security_group_egress_rules_all = coalesce(
    var.node_security_group_additional_rules.egress,
    local.node_security_group_egress_rules_default,
  )
}
