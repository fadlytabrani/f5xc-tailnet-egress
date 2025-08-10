# F5 XC Tailnet Egress

A Terraform-based solution to generate manifests for connecting F5 Distributed Cloud to multiple Tailscale networks through a single Kubernetes deployment using containerized proxy solutions.

## 🌟 Features

- **Multi-Tailnet Support**: Connect to multiple Tailscale networks simultaneously
- **Proxy-Based Routing**: High-performance L4 proxy containers with advanced traffic management
- **Kubernetes Native**: Secure secret management with RBAC
- **Dynamic Configuration**: Automatic port allocation and service discovery

## 🏗️ Architecture

_[Architecture diagram will be provided as an SVG file]_

### **🔍 Architecture Components Explained:**

#### **F5 XC Layer**

- **Origin Pools**: Define backend services for load balancing
- **Health Checks**: Monitor service availability
- **Traffic Distribution**: Route requests to healthy endpoints

#### **Kubernetes Layer**

- **Service**: Exposes multiple ports (10000, 11000, 12000, etc.)
- **StatefulSet**: Ensures stable network identities
- **RBAC**: Secure access to secrets and resources
- **ConfigMaps**: Proxy configuration templates

#### **Proxy Layer**

- **Proxy Container**: L4 TCP proxy with tunneling support
- **Listeners**: One per service port (10000 + tailnet_index \* 1000 + service_index)
- **Backend Routing**: Route traffic directly to Tailscale network services
- **Userspace Mode**: Containers run in userspace mode for enhanced security and isolation

#### **Service Layer**

- **Dynamic Discovery**: Services accessible via Tailscale hostnames
- **Port Mapping**: Internal service ports preserved
- **Protocol Support**: TCP tunneling through Tailscale mesh

## 🚀 Quick Start

1. **Clone the repository**:

   ```bash
   git clone <repository-url>
   cd f5xc-tailnet-egress
   ```

2. **Configure your tailnets**:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your tailnet configurations
   ```

3. **Deploy the egress service**:

   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Apply the Kubernetes manifests**:
   ```bash
   kubectl apply -f outputs/envoy/manifests/
   ```

> **Note**: The current implementation uses Envoy proxy containers, but the architecture is designed to support other proxy solutions. You can modify the container images and configurations in the templates to use alternative proxies like Caddy, socat, gost, tail4ward, or custom solutions. The port allocation and routing logic is proxy-agnostic. More proxy configurations will be added to the project soon.

## 📋 Configuration

### Basic Multi-Tailnet Setup

```hcl
tailnets = [
  {
    tailnet_name = "production"
    tailnet_auth_key = "tskey-auth-..."
    services = [
      {
        endpoint = "app.production.ts.net"
        protocol = "tcp"
        port = 80
      }
    ]
  },
  {
    tailnet_name = "staging"
    tailnet_auth_key = "tskey-auth-..."
    services = [
      {
        endpoint = "api.staging.ts.net"
        protocol = "tcp"
        port = 3000
      }
    ]
  }
]
```

### Using Kubernetes Secrets

```hcl
tailnets = [
  {
    tailnet_name = "production"
    tailnet_auth_key = "tskey-auth-..."
    use_k8s_secret = true  # Enables RBAC and secret management
    services = [...]
  }
]
```

## 🔧 Port Allocation

The egress service uses a systematic port allocation scheme that works with any L4 proxy container:

- **Service Ports**: `10000 + (tailnet_index * 1000) + service_index`

Example:

- Tailnet 0: ports 10000-10999
- Tailnet 1: ports 11000-11999
- Tailnet 2: ports 12000-12999

## 🔐 Security Features

- **RBAC Integration**: Automatic ServiceAccount, Role, and RoleBinding generation
- **Secret Management**: Secure storage of Tailscale authentication keys

## 📖 Documentation

- [Envoy Solution](docs/envoy.md) - Envoy proxy implementation details

## 🛠️ Requirements

- Terraform >= 1.0
- Kubernetes cluster with RBAC enabled
- Tailscale authentication keys
- F5 Distributed Cloud access

## 🌐 Kubernetes Compatibility

These solutions are designed for standard Kubernetes distributions but can also be deployed on other Kubernetes distributions.

## 🏢 F5 XC Deployment Options

On F5 Distributed Cloud (F5 XC), these solutions can be deployed on:

- **Regional Edges (RE)**: For centralized, multi-region traffic management
- **Customer Edges (CE)**: For local, on-premises or edge deployments

This flexibility allows you to choose the optimal deployment model based on your network architecture and requirements.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests and documentation
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License. See [LICENSE.md](LICENSE.md) for full details.

## 🆘 Support

For issues and questions:

- Open an issue on GitHub
- Review the example configurations

## 🔄 Deployment

Use the included deployment script for easy deployment:

```bash
./deploy.sh
```

This script will:

1. Initialize Terraform
2. Plan the deployment
3. Apply the configuration
4. Generate Kubernetes manifests
5. Apply manifests to your cluster
