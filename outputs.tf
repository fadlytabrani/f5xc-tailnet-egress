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

output "tailnet_proxy_ports" {
  description = "Tailscale HTTP proxy ports for each tailnet"
  value = {
    for index, tailnet in var.tailnets :
    tailnet.tailnet_name => 10550 + index
  }
}

output "f5xc_origin_pools" {
  description = "F5 XC Origin Pool mappings for services"
  value = flatten([
    for tailnet_index, tailnet in var.tailnets : [
      for service_index, service in tailnet.services : {
        f5xc_origin_pool = service.f5xc_origin_pool
        tailnet_name     = tailnet.tailnet_name
        endpoint         = service.endpoint
        exposed_port     = 10000 + (tailnet_index * 1000) + service_index
        service_endpoint = "tailscale-egress.${var.k8s_namespace}:${10000 + (tailnet_index * 1000) + service_index}"
      }
    ]
  ])
}

output "k8s_namespace" {
  description = "Kubernetes namespace where resources will be deployed"
  value       = var.k8s_namespace
}

output "kubernetes_manifests" {
  description = "Generated Kubernetes manifest file paths"
  value = {
    service     = "${path.module}/outputs/envoy/manifests/04-service.yaml"
    configmap   = "${path.module}/outputs/envoy/manifests/05-configmap.yaml"
    statefulset = "${path.module}/outputs/envoy/manifests/06-statefulset.yaml"
    rbac_files = anytrue([for tailnet in var.tailnets : tailnet.use_k8s_secret]) ? [
      "${path.module}/outputs/envoy/manifests/00-secrets.yaml",
      "${path.module}/outputs/envoy/manifests/01-serviceaccount.yaml",
      "${path.module}/outputs/envoy/manifests/02-role.yaml",
      "${path.module}/outputs/envoy/manifests/03-rolebinding.yaml"
    ] : []
  }
}

output "documentation" {
  description = "Generated documentation file paths"
  value = {
    configuration_summary = "${path.module}/outputs/configuration-summary.md"
  }
}
