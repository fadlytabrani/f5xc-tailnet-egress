variable "output_dir" {
  description = "Target directory for generated origin pool JSON files"
  type        = string
}

variable "k8s_namespace" {
  description = "Kubernetes namespace where the egress service is deployed"
  type        = string
}

variable "services" {
  description = "Flattened list of all services across all tailnets"
  type = list(object({
    global_index     = number
    tailnet_index    = number
    service_index    = number
    tailnet_name     = string
    endpoint         = string
    f5xc_origin_pool = string
    port             = number
    protocol         = string
    exposed_port     = number
    service_endpoint = string
  }))
}

variable "origin_pool_suffixes" {
  description = "List of random ID objects for unique origin pool suffixes"
  type        = any
}
