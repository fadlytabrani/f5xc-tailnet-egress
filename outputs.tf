output "proxy_type" {
  description = "Selected proxy type implementation"
  value       = var.proxy_type
}

output "k8s_namespace" {
  description = "Kubernetes namespace where resources will be deployed"
  value       = var.k8s_namespace
}

output "service_ports" {
  description = "Port mappings for all services across all tailnets"
  value = flatten([
    for tailnet_index, tailnet in var.tailnets : [
      for service_index, service in tailnet.services : {
        tailnet_name     = tailnet.tailnet_name
        service_index    = service_index
        endpoint         = service.endpoint
        port             = service.port
        protocol         = service.protocol
        exposed_port     = 10000 + (tailnet_index * 1000) + service_index
        proxy_port       = 10550 + tailnet_index
        f5xc_origin_pool = service.f5xc_origin_pool
      }
    ]
  ])
}

output "f5xc_origin_pools" {
  description = "F5 XC Origin Pool mappings for services"
  value = [
    for service in local.all_services : {
      f5xc_origin_pool        = service.f5xc_origin_pool
      f5xc_origin_pool_unique = "${service.f5xc_origin_pool}-${random_id.origin_pool_suffix[service.global_index].hex}"
      tailnet_name            = service.tailnet_name
      endpoint                = service.endpoint
      protocol                = service.protocol
      exposed_port            = service.exposed_port
      service_endpoint        = service.service_endpoint
    }
  ]
}

output "kubernetes_manifests" {
  description = "Generated Kubernetes manifest file paths for the active proxy"
  value = var.proxy_type == "envoy" ? module.envoy[0].manifest_files : module.proxtail[0].manifest_files
}

output "origin_pool_configs" {
  description = "Generated F5 XC origin pool JSON configuration file paths"
  value       = module.f5xc.origin_pool_files
}

output "documentation" {
  description = "Generated documentation file paths for the active proxy"
  value = {
    configuration_summary = var.proxy_type == "envoy" ? module.envoy[0].configuration_summary : module.proxtail[0].configuration_summary
  }
}
