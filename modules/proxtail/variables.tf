variable "output_dir" {
  description = "Target directory for Proxtail Kubernetes manifests"
  type        = string
}

variable "summary_output_dir" {
  description = "Target directory for Proxtail configuration summary"
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

variable "replicas" {
  description = "Number of StatefulSet pod replicas"
  type        = number
  default     = 1
}

variable "enable_upstream_probe" {
  description = "Enable active upstream TCP/UDP reachability probing in proxtail"
  type        = bool
  default     = false
}

variable "tailnets" {
  description = "List of tailnets and their services"
  type        = any
}

variable "pool_name_map" {
  description = "Map of original origin pool names to unique suffixed names"
  type        = map(string)
}
