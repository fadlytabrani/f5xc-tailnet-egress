variable "output_dir" {
  description = "Target directory for Envoy Kubernetes manifests"
  type        = string
}

variable "summary_output_dir" {
  description = "Target directory for Envoy configuration summary"
  type        = string
}

variable "k8s_namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "container_registry" {
  description = "Container registry to pull images from"
  type        = string
}

variable "tailnets" {
  description = "List of tailnets and their services"
  type        = any
}

variable "pool_name_map" {
  description = "Map of original origin pool names to unique suffixed names"
  type        = map(string)
}
