variable "k8s_namespace" {
  description = "Kubernetes namespace where resources will be deployed"
  type        = string
  default     = "default"
}

variable "container_registry" {
  description = "Alternative to container registry to use for downloadingn images"
  type        = string
  default     = "docker.io"
}

variable "tailnets" {
  description = "List of tailnets and the services that are going to be proxied"
  type = list(object({

    # Name of the tailnet.
    tailnet_name = string

    # Authentication key for the tailnet (can be OAuth key or Auth key).
    tailnet_key = string

    # Advertise tags for the proxynode. Tags must already exist in the tailnet. Eg: "tag:server,tag:development"
    tailnet_advertise_tags = optional(string)

    # Optional flag to use Kubernetes secret for the tailnet keys. This will generate associated manifests, such as secrets roles and rolebindings.
    use_k8s_secret = optional(bool, false)

    # List of services in the tailnet that will be accessible to F5XC.
    services = list(object({

      # IP address or hostname of the endpoint in the tailnet.
      endpoint = string

      # Protocol of the service, either "tcp" or "udp".
      protocol = string

      # Port number of the service in the tailnet.
      port = number

      # Connection timeout for the service in seconds.
      connection_timeout = optional(number, 5)

      # F5 XC Origin Pool name that this endpoint will be associated with.
      f5xc_origin_pool = string
    }))
  }))

  validation {
    condition = alltrue([
      for tailnet in var.tailnets :
      tailnet.tailnet_key != ""
    ])
    error_message = "Each tailnet must have a non-empty tailnet_key specified."
  }

  validation {
    condition = alltrue([
      for tailnet in var.tailnets :
      alltrue([
        for service in tailnet.services :
        contains(["tcp", "udp"], service.protocol)
      ])
    ])
    error_message = "Service protocol must be either 'tcp' or 'udp'."
  }
}
