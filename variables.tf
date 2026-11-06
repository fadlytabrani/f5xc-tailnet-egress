variable "proxy_type" {
  description = "Proxy implementation to generate manifests for (envoy, proxtail)"
  type        = string
  default     = "proxtail"

  validation {
    condition     = contains(["envoy", "proxtail"], var.proxy_type)
    error_message = "proxy_type must be either 'envoy' or 'proxtail'."
  }
}

variable "k8s_namespace" {
  description = "Kubernetes namespace where resources will be deployed"
  type        = string
  default     = "default"
}

variable "container_registry" {
  description = "Container registry to use for downloading images"
  type        = string
  default     = "docker.io"
}

variable "replicas" {
  description = "Number of StatefulSet pod replicas to deploy for horizontal scaling"
  type        = number
  default     = 1

  validation {
    condition     = var.replicas >= 1 && floor(var.replicas) == var.replicas
    error_message = "replicas must be an integer greater than or equal to 1."
  }
}

variable "f5xc_virtual_site" {
  description = "F5 XC virtual site name in the shared namespace for Origin Pool k8s_service discovery"
  type        = string
  default     = "ves-io-all-res"
}

variable "enable_upstream_probe" {
  description = "Enable active upstream TCP/UDP reachability probing and automatic local listener suspension in proxtail"
  type        = bool
  default     = false
}

variable "tailnets" {
  description = "List of tailnets and the services that are going to be proxied"
  type = list(object({

    # Name of the tailnet (mapped to tailnets[].profile in proxtail).
    tailnet_name = string

    # Authentication key for the tailnet (can be OAuth client secret or reusable Auth key).
    tailnet_key = string

    # Advertise tags for the proxy node. Tags must already exist in the tailnet. Eg: "tag:server,tag:development"
    tailnet_advertise_tags = optional(string)

    # Optional flag to use Kubernetes secret for the tailnet keys. This will generate associated manifests, such as secrets, roles, and rolebindings.
    use_k8s_secret = optional(bool, false)

    # Optional custom coordination server URL (e.g., Headscale) for proxtail.
    control_url = optional(string)

    # Optional flag to automatically discover and proxy Tailscale VIP services onto ports 30000-30999 in proxtail.
    auto_proxy_vips = optional(bool, false)

    # List of services in the tailnet that will be accessible to F5XC.
    services = list(object({

      # IP address or hostname of the endpoint in the tailnet.
      endpoint = string

      # Protocol of the service, either "tcp" or "udp".
      protocol = string

      # Port number of the service in the tailnet.
      port = number

      # Connection/idle timeout for the service in seconds (defaults to 30s for proxtail, 5s for envoy).
      connection_timeout = optional(number)

      # Optional per-port override for active upstream reachability probing in proxtail.
      probe = optional(bool)

      # F5 XC Origin Pool name that this endpoint will be associated with.
      f5xc_origin_pool = string
    }))
  }))

  validation {
    condition = alltrue([
      for tailnet in var.tailnets :
      trimspace(tailnet.tailnet_key) != ""
    ])
    error_message = "Each tailnet must have a non-empty tailnet_key specified."
  }

  validation {
    condition     = length(distinct([for tailnet in var.tailnets : tailnet.tailnet_name])) == length(var.tailnets)
    error_message = "Each tailnet must have a unique tailnet_name."
  }

  validation {
    condition = alltrue([
      for tailnet in var.tailnets :
      alltrue([
        for service in tailnet.services :
        contains(["tcp", "udp"], lower(service.protocol))
      ])
    ])
    error_message = "Service protocol must be either 'tcp' or 'udp'."
  }

  validation {
    condition = var.proxy_type != "envoy" || alltrue([
      for tailnet in var.tailnets :
      alltrue([
        for service in tailnet.services :
        lower(service.protocol) == "tcp"
      ])
    ])
    error_message = "The Envoy proxy implementation only supports 'tcp' protocol. Use 'proxtail' for UDP support."
  }

  validation {
    condition = length(distinct(flatten([
      for tailnet in var.tailnets : [
        for service in tailnet.services : service.f5xc_origin_pool
      ]
      ]))) == length(flatten([
      for tailnet in var.tailnets : tailnet.services
    ]))
    error_message = "Each service must specify a unique f5xc_origin_pool name."
  }
}
