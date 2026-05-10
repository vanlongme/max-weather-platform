locals {
  namespaces = {
    "weather-staging" = { env = "staging" }
    "weather-prod"    = { env = "prod" }
  }
}

resource "kubernetes_namespace_v1" "this" {
  for_each = local.namespaces

  metadata {
    name = each.key
    labels = {
      env        = each.value.env
      managed-by = "terraform"
    }
  }
}

resource "kubernetes_resource_quota_v1" "this" {
  for_each = local.namespaces

  metadata {
    name      = "default-quota"
    namespace = kubernetes_namespace_v1.this[each.key].metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = "4"
      "requests.memory" = "8Gi"
      "limits.cpu"      = "8"
      "limits.memory"   = "16Gi"
      "pods"            = "50"
    }
  }
}

resource "kubernetes_limit_range_v1" "this" {
  for_each = local.namespaces

  metadata {
    name      = "default-limits"
    namespace = kubernetes_namespace_v1.this[each.key].metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "500m"
        memory = "512Mi"
      }
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "deny_all_ingress" {
  for_each = local.namespaces

  metadata {
    name      = "deny-all-ingress"
    namespace = kubernetes_namespace_v1.this[each.key].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy_v1" "allow_from_ingress_nginx" {
  for_each = local.namespaces

  metadata {
    name      = "allow-from-ingress-nginx"
    namespace = kubernetes_namespace_v1.this[each.key].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "ingress-nginx"
          }
        }
      }
    }
  }
}
