# Envoy Solution

This document explains how the Envoy proxy solution works.

## How It Works

The Envoy solution provides an L4 TCP proxy that routes traffic from F5 XC to multiple Tailscale networks through a multi-container architecture.

### Core Architecture

1. **F5 XC Layer**: Origin pools send traffic to the Kubernetes service based on health checks and load balancing policies
2. **Kubernetes Service**: Exposes multiple ports (10000, 11000, 12000, etc.) for different tailnets
3. **Envoy Proxy Container**: Listens on configured ports and routes traffic to local Tailscale HTTP proxies
4. **Tailscale HTTP Proxy Containers**: Multiple isolated containers, one per tailnet, each running an HTTP proxy service
5. **Tailscale Integration**: Connection to remote services through Tailscale mesh VPN

### Traffic Flow

```
F5 XC → Kubernetes Service → Envoy Proxy → Local Tailscale HTTP Proxy → Tailscale Network → Target Service
```

Traffic flows through:

- **External**: F5 XC routes traffic to Kubernetes service ports
- **Internal**: Envoy proxy forwards to local HTTP proxy containers
- **Network**: HTTP proxy containers establish connections through Tailscale mesh VPN
- **Destination**: Traffic reaches target services in remote Tailscale networks

### Port Allocation

- **Service Ports**: `10000 + (tailnet_index * 1000) + service_index`

  - **Tailnet 0**: Ports 10000-10999
  - **Tailnet 1**: Ports 11000-11999
  - **Tailnet 2**: Ports 12000-12999

- **Tailscale HTTP Proxy Ports**: `10550 + tailnet_index`
  - **Tailnet 0**: HTTP proxy on port 10550
  - **Tailnet 1**: HTTP proxy on port 10551
  - **Tailnet 2**: HTTP proxy on port 10552

### Envoy Configuration

- **Listeners**: One per service port, configured for TCP connections
- **Clusters**: Route definitions forwarding to local Tailscale HTTP proxy endpoints
- **TCP Proxy**: L4 traffic forwarding with connection pooling and health checking
- **Dynamic Updates**: Configuration updates via ConfigMaps without restart

### Tailscale HTTP Proxy Containers

Each tailnet gets its own container:

- **Isolation**: Separate containers with individual `/var/run` volumes
- **Authentication**: Independent Tailscale authentication per container
- **HTTP Proxy Service**: Each container runs an HTTP proxy on port (10550+N)
- **Mesh VPN**: Secure connectivity through Tailscale's encrypted mesh network
- **Shields-Up Mode**: Security configuration with `tag:f5xc-egress`

### Container Architecture

```
Pod: tailscale-egress
├── Envoy Proxy Container
│   ├── Listener: Port 10000 (Tailnet 0)
│   ├── Listener: Port 11000 (Tailnet 1)
│   ├── Listener: Port 12000 (Tailnet 2)
│   └── Routes traffic to local HTTP proxies
├── Tailscale Container 0 (Tailnet 0)
│   ├── HTTP Proxy: Port 10550
│   ├── Auth Key: Tailnet 0 specific
│   └── Volume: /var/run-0
├── Tailscale Container 1 (Tailnet 1)
│   ├── HTTP Proxy: Port 10551
│   ├── Auth Key: Tailnet 1 specific
│   └── Volume: /var/run-1
└── Tailscale Container N (Tailnet N)
    ├── HTTP Proxy: Port 10550+N
    ├── Auth Key: Tailnet N specific
    └── Volume: /var/run-N
```
