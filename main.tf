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

locals {
  # Create a flat list of all services across all tailnets with calculated port mappings
  all_services = flatten([
    for tailnet_index, tailnet in var.tailnets : [
      for service_index, service in tailnet.services : {
        global_index     = length(flatten([for t in slice(var.tailnets, 0, tailnet_index) : t.services])) + service_index
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

  pool_name_map = {
    for service in local.all_services : service.f5xc_origin_pool => "${service.f5xc_origin_pool}-${random_id.origin_pool_suffix[service.global_index].hex}"...
  }
}

# Generate unique suffixes for origin pool names to avoid naming conflicts
resource "random_id" "origin_pool_suffix" {
  count       = length(local.all_services)
  byte_length = 4
  keepers = {
    tailnet_config = jsonencode(var.tailnets)
  }
}

# Generate F5 XC Origin Pool JSON configurations
module "f5xc" {
  source               = "./modules/f5xc"
  output_dir           = "${path.module}/outputs/${var.proxy_type}/f5xc"
  k8s_namespace        = var.k8s_namespace
  services             = local.all_services
  origin_pool_suffixes = random_id.origin_pool_suffix
}

# Generate Envoy proxy manifests
module "envoy" {
  count              = var.proxy_type == "envoy" ? 1 : 0
  source             = "./modules/envoy"
  output_dir         = "${path.module}/outputs/envoy/k8s"
  summary_output_dir = "${path.module}/outputs/envoy"
  k8s_namespace      = var.k8s_namespace
  container_registry = var.container_registry
  tailnets           = var.tailnets
  pool_name_map = {
    for service in local.all_services : service.f5xc_origin_pool => "${service.f5xc_origin_pool}-${random_id.origin_pool_suffix[service.global_index].hex}"
  }
}

# Generate Proxtail proxy manifests
module "proxtail" {
  count              = var.proxy_type == "proxtail" ? 1 : 0
  source             = "./modules/proxtail"
  output_dir         = "${path.module}/outputs/proxtail/k8s"
  summary_output_dir = "${path.module}/outputs/proxtail"
  k8s_namespace      = var.k8s_namespace
  container_registry = var.container_registry
  tailnets           = var.tailnets
  pool_name_map = {
    for service in local.all_services : service.f5xc_origin_pool => "${service.f5xc_origin_pool}-${random_id.origin_pool_suffix[service.global_index].hex}"
  }
}
