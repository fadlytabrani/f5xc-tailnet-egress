terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Generate Service for multi-tailnet egress - Envoy
resource "local_file" "envoy_service" {
  content = templatefile("./envoy/k8s/service.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${path.module}/outputs/envoy/k8s/04-service.yaml"
}

# Generate RBAC resources only if any tailnet uses k8s secrets - Envoy
resource "local_file" "envoy_serviceaccount" {
  count = anytrue([for tailnet in var.tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("./envoy/k8s/serviceaccount.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${path.module}/outputs/envoy/k8s/01-serviceaccount.yaml"
}

resource "local_file" "envoy_role" {
  count = anytrue([for tailnet in var.tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("./envoy/k8s/role.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${path.module}/outputs/envoy/k8s/02-role.yaml"
}

resource "local_file" "envoy_rolebinding" {
  count = anytrue([for tailnet in var.tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("./envoy/k8s/rolebinding.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${path.module}/outputs/envoy/k8s/03-rolebinding.yaml"
}



# Generate secrets for tailnets that use k8s secrets - Envoy
resource "local_file" "envoy_secrets" {
  count = anytrue([for tailnet in var.tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("./envoy/k8s/secrets.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${path.module}/outputs/envoy/k8s/00-secrets.yaml"
}



# Generate ConfigMap - Envoy
resource "local_file" "envoy_configmap" {
  content = templatefile("./envoy/k8s/configmap.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${path.module}/outputs/envoy/k8s/05-configmap.yaml"
}



# Generate StatefulSet - Envoy
resource "local_file" "envoy_statefulset" {
  content = templatefile(
    anytrue([for tailnet in var.tailnets : tailnet.use_k8s_secret])
    ? "./envoy/k8s/statefulset-secrets.yaml.tftpl"
    : "./envoy/k8s/statefulset.yaml.tftpl",
    {
      tailnets      = var.tailnets
      k8s_namespace = var.k8s_namespace
    }
  )
  filename = "${path.module}/outputs/envoy/k8s/06-statefulset.yaml"
}



# Generate unique suffixes for origin pool names to avoid conflicts
resource "random_id" "origin_pool_suffix" {
  count       = length(flatten([for tailnet in var.tailnets : tailnet.services]))
  byte_length = 4
  keepers = {
    # Regenerate suffixes when tailnet configuration changes
    tailnet_config = jsonencode(var.tailnets)
  }
}

# Generate origin pool JSON configurations for F5 XC API
resource "local_file" "origin_pool_configs" {
  count = length(flatten([for tailnet in var.tailnets : tailnet.services]))
  content = templatefile("${path.module}/envoy/f5xc/origin_pool.json.tftpl", {
    origin_pool_name = "${local.all_services[count.index].f5xc_origin_pool}-${random_id.origin_pool_suffix[count.index].hex}"
    namespace        = var.k8s_namespace
    service_endpoint = local.all_services[count.index].service_endpoint
    exposed_port     = local.all_services[count.index].exposed_port
    protocol         = local.all_services[count.index].protocol
  })
  filename = "${path.module}/outputs/envoy/f5xc/${local.all_services[count.index].f5xc_origin_pool}-${random_id.origin_pool_suffix[count.index].hex}.json"
}

# Generate configuration summary documentation - Envoy
resource "local_file" "envoy_configuration_summary_doc" {
  content = templatefile("./envoy/configuration-summary.md.tftpl", {
    tailnets      = var.tailnets
    k8s_namespace = var.k8s_namespace
    pool_name_map = {
      for service in local.all_services : service.f5xc_origin_pool => "${service.f5xc_origin_pool}-${random_id.origin_pool_suffix[service.global_index].hex}"
    }
  })
  filename = "${path.module}/outputs/envoy/configuration-summary.md"
}


