# Proxtail Solution

This document explains how the [Proxtail](https://github.com/fadlytabrani/proxtail) proxy solution works in F5 XC Tailnet Egress.

## Overview

`proxtail` is a lightweight, high-performance Layer 4 (TCP & UDP) reverse proxy powered by Tailscale's userspace networking engine ([`tsnet`](https://pkg.go.dev/tailscale.com/tsnet)). 

Unlike the multi-container Envoy architecture which requires an Envoy proxy chained to separate Tailscale sidecar containers running `containerboot`, `proxtail` runs as a **single container** with native multi-tailnet and protocol support.

```
F5 XC → Kubernetes Service → Proxtail (Single Container StatefulSet) → Tailscale Mesh → Target Service
```

## How It Works

1. **F5 XC Layer**: F5 XC Origin Pools send traffic to the Kubernetes Service on exposed ports (`10000`, `11000`, etc.).
2. **Kubernetes Service**: Headless Service `tailscale-egress` exposes all TCP and UDP ports mapped to the `StatefulSet`.
3. **Proxtail StatefulSet**:
   - Single unprivileged container running as non-root (UID `10001`).
   - Compliant with Kubernetes Pod Security Standards `restricted` profile.
   - Embeds Tailscale's WireGuard stack directly in userspace via `tsnet`.
   - Listens on local ports and forwards traffic directly into the isolated `tsnet` network stack of the corresponding tailnet.
4. **Tailscale Mesh**: Secure end-to-end WireGuard tunnel connects to target services via MagicDNS hostnames or IP addresses.

## Key Features

- **Single Container Simplicity**: No internal proxy hopping over loopback or complex sidecar process coordination.
- **Full TCP and UDP Support**: Transparently tunnels both TCP and UDP protocols (e.g. HTTP, gRPC, databases, DNS, UDP streaming).
- **Ephemeral State**: State is kept in-memory (`ephemeral: true`). When the pod restarts or updates, `proxtail` executes a graceful logout via `b.Logout()`, cleanly deregistering the ephemeral node in `< 150ms`.
- **Predictable Hostnames**: Deployed as a `StatefulSet`, the pod hostname evaluates to `tailscale-egress-0`. Tailscale node names appear predictably in your Tailscale Admin Console as:
  ```text
  proxtail-<tailnet_name>-tailscale-egress-0
  ```
- **Built-in Observability**:
  - `/healthz` and `/readyz` probes on port `9000`
  - Prometheus metrics on port `9000` (`/metrics`)
  - Periodic traffic throughput logging

## Kubernetes Architecture

```
Pod: tailscale-egress-0
└── Container: proxtail (UID 10001)
    ├── Health & Metrics Listener: Port 9000 (/healthz, /readyz, /metrics)
    ├── Local Port Listeners (10000, 11000, ...)
    ├── Tailnet 0 tsnet Engine (In-Memory WireGuard)
    ├── Tailnet 1 tsnet Engine (In-Memory WireGuard)
    └── Tailnet N tsnet Engine (In-Memory WireGuard)
```

## Configuration File Format

The ConfigMap generates `/etc/proxtail/config.yaml`:

```yaml
proxy:
  health_port: 9000
  metrics_interval: 60
tailnets:
  - name: "tailnet0"
    hostname: "proxtail-tailnet0-${HOSTNAME}"
    ephemeral: true
    ports:
      - port: 10000
        destination: "app.tailnet0.ts.net:80"
        protocol: "tcp"
        timeout: 10
  - name: "tailnet1"
    hostname: "proxtail-tailnet1-${HOSTNAME}"
    ephemeral: true
    ports:
      - port: 11000
        destination: "dns.tailnet1.ts.net:53"
        protocol: "udp"
        timeout: 15
```

## Secret Management

When `use_k8s_secret = true`, authentication keys are stored in Kubernetes Secrets and injected into environment variables:
- `TS_AUTHKEY_<TAILNET_NAME>`: Tailscale auth key (must be marked **Reusable** in Tailscale Admin Console) or OAuth Client Secret (`tskey-client-...`).
