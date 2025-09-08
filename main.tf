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
  count = length(local.envoy_tailnets) > 0 ? 1 : 0
  content = templatefile("./envoy/k8s/service.yaml.tftpl", {
    tailnets = local.envoy_tailnets
  })
  filename = "${path.module}/outputs/envoy/k8s/04-service.yaml"
}

# Generate RBAC resources only if any tailnet uses k8s secrets - Envoy
resource "local_file" "envoy_serviceaccount" {
  count = length(local.envoy_tailnets) > 0 && anytrue([for tailnet in local.envoy_tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("./envoy/k8s/serviceaccount.yaml.tftpl", {
    tailnets = local.envoy_tailnets
  })
  filename = "${path.module}/outputs/envoy/k8s/01-serviceaccount.yaml"
}

resource "local_file" "envoy_role" {
  count = length(local.envoy_tailnets) > 0 && anytrue([for tailnet in local.envoy_tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("./envoy/k8s/role.yaml.tftpl", {
    tailnets = local.envoy_tailnets
  })
  filename = "${path.module}/outputs/envoy/k8s/02-role.yaml"
}

resource "local_file" "envoy_rolebinding" {
  count = length(local.envoy_tailnets) > 0 && anytrue([for tailnet in local.envoy_tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("./envoy/k8s/rolebinding.yaml.tftpl", {
    tailnets = local.envoy_tailnets
  })
  filename = "${path.module}/outputs/envoy/k8s/03-rolebinding.yaml"
}

# Generate secrets for tailnets that use k8s secrets - Envoy
resource "local_file" "envoy_secrets" {
  count = length(local.envoy_tailnets) > 0 && anytrue([for tailnet in local.envoy_tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("./envoy/k8s/secrets.yaml.tftpl", {
    tailnets = local.envoy_tailnets
  })
  filename = "${path.module}/outputs/envoy/k8s/00-secrets.yaml"
}

# Generate ConfigMap - Envoy
resource "local_file" "envoy_configmap" {
  count = length(local.envoy_tailnets) > 0 ? 1 : 0
  content = templatefile("./envoy/k8s/configmap.yaml.tftpl", {
    tailnets = local.envoy_tailnets
  })
  filename = "${path.module}/outputs/envoy/k8s/05-configmap.yaml"
}

# Generate StatefulSet - Envoy
resource "local_file" "envoy_statefulset" {
  count = length(local.envoy_tailnets) > 0 ? 1 : 0
  content = templatefile(
    anytrue([for tailnet in local.envoy_tailnets : tailnet.use_k8s_secret])
    ? "./envoy/k8s/statefulset-secrets.yaml.tftpl"
    : "./envoy/k8s/statefulset.yaml.tftpl",
    {
      tailnets           = local.envoy_tailnets
      k8s_namespace      = var.k8s_namespace
      container_registry = var.container_registry
    }
  )
  filename = "${path.module}/outputs/envoy/k8s/06-statefulset.yaml"
}



# Generate unique suffixes for envoy origin pool names to avoid conflicts
resource "random_id" "envoy_origin_pool_suffix" {
  count       = length(local.envoy_services)
  byte_length = 4
  keepers = {
    # Regenerate suffixes when envoy tailnet configuration changes
    envoy_tailnet_config = jsonencode(local.envoy_tailnets)
  }
}


# Filter tailnets to only include TCP/UDP services for envoy
locals {
  envoy_tailnets = [
    for tailnet in var.tailnets : {
      tailnet_name           = tailnet.tailnet_name
      tailnet_key            = tailnet.tailnet_key
      tailnet_advertise_tags = tailnet.tailnet_advertise_tags
      use_k8s_secret         = tailnet.use_k8s_secret
      services = [
        for service in tailnet.services : service
        if contains(["tcp", "udp"], service.protocol)
      ]
    }
    if length([
      for service in tailnet.services : service
      if contains(["tcp", "udp"], service.protocol)
    ]) > 0
  ]

  # Create a flat list of all TCP/UDP services for envoy
  envoy_services = flatten([
    for tailnet_index, tailnet in local.envoy_tailnets : [
      for service_index, service in tailnet.services : {
        global_index     = length(flatten([for t in slice(local.envoy_tailnets, 0, tailnet_index) : t.services])) + service_index
        tailnet_index    = tailnet_index
        service_index    = service_index
        tailnet_name     = tailnet.tailnet_name
        endpoint         = service.endpoint
        f5xc_origin_pool = service.f5xc_origin_pool
        port             = service.port
        protocol         = service.protocol
        exposed_port     = 10000 + (tailnet_index * 1000) + service_index
        service_endpoint = "tailscale-egress.${var.k8s_namespace}:${10000 + (tailnet_index * 1000) + service_index}"
      }
    ]
  ])

  # Filter tailnets to only include HTTP/HTTPS services for tailscaled
  tailscaled_tailnets = [
    for tailnet_index, tailnet in var.tailnets : {
      tailnet_index          = tailnet_index
      tailnet_name           = tailnet.tailnet_name
      tailnet_key            = tailnet.tailnet_key
      tailnet_advertise_tags = tailnet.tailnet_advertise_tags
      use_k8s_secret         = tailnet.use_k8s_secret
      services = [
        for service in tailnet.services : service
        if contains(["http", "https"], service.protocol)
      ]
    }
    if length([
      for service in tailnet.services : service
      if contains(["http", "https"], service.protocol)
    ]) > 0
  ]

  # Create a flat list of all HTTP/HTTPS services for tailscaled
  tailscaled_services = flatten([
    for tailnet_index, tailnet in local.tailscaled_tailnets : [
      for service_index, service in tailnet.services : {
        global_index     = length(flatten([for t in slice(local.tailscaled_tailnets, 0, tailnet_index) : t.services])) + service_index
        tailnet_index    = tailnet.tailnet_index # Use original tailnet index
        service_index    = service_index
        tailnet_name     = tailnet.tailnet_name
        endpoint         = service.endpoint
        f5xc_origin_pool = service.f5xc_origin_pool
        port             = service.port
        protocol         = service.protocol
        exposed_port     = 10000 + (tailnet.tailnet_index * 1000) + service_index
        service_endpoint = "tailscale-egress.${var.k8s_namespace}:${10000 + (tailnet.tailnet_index * 1000) + service_index}"
      }
    ]
  ])
}

# Generate origin pool JSON configurations for F5 XC API - Envoy
resource "local_file" "origin_pool_configs" {
  count = length(local.envoy_services)
  content = templatefile("${path.module}/envoy/f5xc/origin_pool.json.tftpl", {
    origin_pool_name = "${local.envoy_services[count.index].f5xc_origin_pool}-${random_id.envoy_origin_pool_suffix[count.index].hex}"
    namespace        = var.k8s_namespace
    service_endpoint = local.envoy_services[count.index].service_endpoint
    exposed_port     = local.envoy_services[count.index].exposed_port
    protocol         = local.envoy_services[count.index].protocol
  })
  filename = "${path.module}/outputs/envoy/f5xc/${local.envoy_services[count.index].f5xc_origin_pool}-${random_id.envoy_origin_pool_suffix[count.index].hex}.json"
}


# Generate configuration summary documentation - Envoy
resource "local_file" "envoy_configuration_summary_doc" {
  count = length(local.envoy_tailnets) > 0 ? 1 : 0
  content = templatefile("./envoy/configuration-summary.md.tftpl", {
    tailnets      = local.envoy_tailnets
    k8s_namespace = var.k8s_namespace
    pool_name_map = {
      for service in local.envoy_services : service.f5xc_origin_pool => "${service.f5xc_origin_pool}-${random_id.envoy_origin_pool_suffix[service.global_index].hex}"
    }
  })
  filename = "${path.module}/outputs/envoy/configuration-summary.md"
}

# Generate unique suffixes for tailscaled origin pool names to avoid conflicts
resource "random_id" "tailscaled_origin_pool_suffix" {
  count       = length(local.tailscaled_services)
  byte_length = 4
  keepers = {
    # Regenerate suffixes when tailscaled tailnet configuration changes
    tailscaled_tailnet_config = jsonencode(local.tailscaled_tailnets)
  }
}

# Generate origin pool JSON configurations for F5 XC API - Tailscaled
resource "local_file" "tailscaled_origin_pool_configs" {
  count = length(local.tailscaled_services)
  content = templatefile("${path.module}/tailscaled/f5xc/origin_pool.json.tftpl", {
    origin_pool_name = "${local.tailscaled_services[count.index].f5xc_origin_pool}-${random_id.tailscaled_origin_pool_suffix[count.index].hex}"
    namespace        = var.k8s_namespace
    tailnet_index    = local.tailscaled_services[count.index].tailnet_index
    protocol         = local.tailscaled_services[count.index].protocol
  })
  filename = "${path.module}/outputs/tailscaled/f5xc/${local.tailscaled_services[count.index].f5xc_origin_pool}-${random_id.tailscaled_origin_pool_suffix[count.index].hex}.json"
}

# Generate Service for multi-tailnet egress - Tailscaled
resource "local_file" "tailscaled_service" {
  count = length(var.tailnets) > 0 ? 1 : 0
  content = templatefile("./tailscaled/k8s/service.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${path.module}/outputs/tailscaled/k8s/04-service.yaml"
}

# Generate RBAC resources only if any tailnet uses k8s secrets - Tailscaled
resource "local_file" "tailscaled_serviceaccount" {
  count = length(local.tailscaled_tailnets) > 0 && anytrue([for tailnet in local.tailscaled_tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("./tailscaled/k8s/serviceaccount.yaml.tftpl", {
    tailnets = local.tailscaled_tailnets
  })
  filename = "${path.module}/outputs/tailscaled/k8s/01-serviceaccount.yaml"
}

resource "local_file" "tailscaled_role" {
  count = length(local.tailscaled_tailnets) > 0 && anytrue([for tailnet in local.tailscaled_tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("./tailscaled/k8s/role.yaml.tftpl", {
    tailnets = local.tailscaled_tailnets
  })
  filename = "${path.module}/outputs/tailscaled/k8s/02-role.yaml"
}

resource "local_file" "tailscaled_rolebinding" {
  count = length(local.tailscaled_tailnets) > 0 && anytrue([for tailnet in local.tailscaled_tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("./tailscaled/k8s/rolebinding.yaml.tftpl", {
    tailnets = local.tailscaled_tailnets
  })
  filename = "${path.module}/outputs/tailscaled/k8s/03-rolebinding.yaml"
}

# Generate secrets for tailnets that use k8s secrets - Tailscaled
resource "local_file" "tailscaled_secrets" {
  count = length(local.tailscaled_tailnets) > 0 && anytrue([for tailnet in local.tailscaled_tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("./tailscaled/k8s/secrets.yaml.tftpl", {
    tailnets = local.tailscaled_tailnets
  })
  filename = "${path.module}/outputs/tailscaled/k8s/00-secrets.yaml"
}

# Generate StatefulSet - Tailscaled
resource "local_file" "tailscaled_statefulset" {
  count = length(var.tailnets) > 0 ? 1 : 0
  content = templatefile(
    anytrue([for tailnet in var.tailnets : tailnet.use_k8s_secret])
    ? "./tailscaled/k8s/statefulset-secrets.yaml.tftpl"
    : "./tailscaled/k8s/statefulset.yaml.tftpl",
    {
      tailnets           = var.tailnets
      k8s_namespace      = var.k8s_namespace
      container_registry = var.container_registry
    }
  )
  filename = "${path.module}/outputs/tailscaled/k8s/06-statefulset.yaml"
}

# Generate configuration summary documentation - Tailscaled
resource "local_file" "tailscaled_configuration_summary_doc" {
  count = length(local.tailscaled_tailnets) > 0 ? 1 : 0
  content = templatefile("./tailscaled/configuration-summary.md.tftpl", {
    tailnets      = local.tailscaled_tailnets
    k8s_namespace = var.k8s_namespace
    all_services  = local.tailscaled_services
    pool_name_map = {
      for service in local.tailscaled_services : service.f5xc_origin_pool => "${service.f5xc_origin_pool}-${random_id.tailscaled_origin_pool_suffix[service.global_index].hex}"
    }
  })
  filename = "${path.module}/outputs/tailscaled/configuration-summary.md"
}





