#!/bin/bash

# F5 XC Tailnet Egress Deployment Script

set -e

# Function to cleanup kubectl proxy on exit
cleanup_proxy() {
    if [ -f ".kubectl-proxy.pid" ]; then
        PROXY_PID=$(cat .kubectl-proxy.pid)
        if kill -0 "$PROXY_PID" 2>/dev/null; then
            echo ""
            echo "🧹 Cleaning up kubectl proxy (PID: $PROXY_PID) on exit..."
            kill "$PROXY_PID" 2>/dev/null || true
            sleep 1
            if kill -0 "$PROXY_PID" 2>/dev/null; then
                kill -9 "$PROXY_PID" 2>/dev/null || true
            fi
        fi
        rm -f .kubectl-proxy.pid
    fi
    
    # Also kill any remaining kubectl proxy processes
    REMAINING_PROXIES=$(pgrep -f "kubectl proxy --port=8001" 2>/dev/null || true)
    if [ -n "$REMAINING_PROXIES" ]; then
        echo "$REMAINING_PROXIES" | while read -r pid; do
            if [ -n "$pid" ]; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
    fi
}

# Set trap to cleanup on script exit
trap cleanup_proxy EXIT

# Configuration - Change this variable to deploy different proxies
PROXY_TYPE=${PROXY_TYPE:-"envoy"}

# Available proxy types: envoy, caddy, haproxy, nginx, socat, gost, tail4ward
# Usage examples:
#   ./deploy.sh                    # Deploy Envoy (default)
#   PROXY_TYPE=caddy ./deploy.sh   # Deploy Caddy
#   PROXY_TYPE=haproxy ./deploy.sh # Deploy HAProxy

echo "🚀 F5 XC Tailnet Egress Deployment - $PROXY_TYPE"
echo "================================================"

# Check prerequisites
echo "📋 Checking prerequisites..."

if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed. Please install Terraform first."
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install kubectl first."
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo "❌ curl is not installed. Please install curl first."
    echo "   Install with: brew install curl (macOS) or apt-get install curl (Ubuntu/Debian)"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "⚠️  jq is not installed. It's recommended for better origin pool detection."
    echo "   Install with: brew install jq (macOS) or apt-get install jq (Ubuntu/Debian)"
    echo "   The script will continue with fallback methods."
fi

if [ ! -f "terraform.tfvars" ]; then
    echo "❌ terraform.tfvars not found. Please copy and configure from examples/terraform.tfvars.example"
    exit 1
fi

echo "✅ Prerequisites check passed"

# Initialize Terraform
echo "🔧 Initializing Terraform..."
terraform init

# Validate configuration
echo "🔍 Validating Terraform configuration..."
terraform validate

# Plan deployment
echo "📝 Planning deployment..."
terraform plan -out=terraform.tfplan

# Ask for confirmation
read -p "🤔 Do you want to apply these changes? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled"
    exit 1
fi

# Apply changes
echo "🏗️  Applying Terraform configuration..."
terraform apply terraform.tfplan

echo "✅ Terraform deployment complete"

    # Check if outputs/envoy/k8s directory exists and has files
    if [ -d "outputs/envoy/k8s" ] && [ "$(ls -A outputs/envoy/k8s)" ]; then
    echo "📦 Applying Kubernetes manifests for $PROXY_TYPE..."
    
    # Check kubectl connection
    if ! kubectl cluster-info &> /dev/null; then
        echo "❌ Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    # Extract namespace from Terraform output
    NAMESPACE=$(terraform output -raw k8s_namespace 2>/dev/null || echo "default")
    echo "🎯 Using namespace: $NAMESPACE"
    
    # Check if namespace exists, fail if it doesn't
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        echo "❌ Namespace '$NAMESPACE' does not exist. Please create it first or check your Terraform configuration."
        exit 1
    fi
    
    # Start kubectl proxy in a separate shell
    echo "🌐 Starting kubectl proxy in a separate shell..."
    echo "   This will allow you to access the Kubernetes API at http://localhost:8001"
    echo "   The proxy will run in the background. To stop it, find the process and kill it."
    
    # Start kubectl proxy in background and capture the PID
    kubectl proxy --port=8001 > /dev/null 2>&1 &
    PROXY_PID=$!
    
    # Wait a moment for the process to start and get the actual PID
    sleep 2
    
    # Verify the process is running and get the actual PID
    if kill -0 "$PROXY_PID" 2>/dev/null; then
        # Double-check by looking for the actual kubectl proxy process
        ACTUAL_PID=$(pgrep -f "kubectl proxy --port=8001" | head -1)
        if [ -n "$ACTUAL_PID" ]; then
            PROXY_PID=$ACTUAL_PID
        fi
        
        # Save PID to a file for easy cleanup
        echo $PROXY_PID > .kubectl-proxy.pid
        
        echo "   ✅ kubectl proxy started with PID: $PROXY_PID"
        echo "   📁 PID saved to .kubectl-proxy.pid for easy cleanup"
        echo "   🚀 Access your cluster at: http://localhost:8001"
        echo "   🛑 To stop proxy: kill $PROXY_PID or run: kill \$(cat .kubectl-proxy.pid)"
    else
        echo "   ❌ Failed to start kubectl proxy"
        exit 1
    fi
    echo ""
    
    # Check for existing F5 XC origin pools to avoid conflicts
    echo "🔍 Checking for existing F5 XC origin pools via API..."
    
            # Get the unique origin pool names from Terraform output
        if command -v jq &> /dev/null; then
            UNIQUE_ORIGIN_POOLS=$(terraform output -json f5xc_origin_pools 2>/dev/null | jq -r '.[].f5xc_origin_pool_unique' 2>/dev/null || echo "")
            BASE_ORIGIN_POOLS=$(terraform output -json f5xc_origin_pools 2>/dev/null | jq -r '.[].f5xc_origin_pool' 2>/dev/null || echo "")
        else
            echo "   ⚠️  jq not found, using fallback method to check origin pools..."
            # Fallback: try to get origin pools using terraform output -raw and grep
            UNIQUE_ORIGIN_POOLS=$(terraform output -raw f5xc_origin_pools 2>/dev/null | grep -o 'ost-[^[:space:]]*' 2>/dev/null || echo "")
            BASE_ORIGIN_POOLS="$UNIQUE_ORIGIN_POOLS"
        fi

        if [ -n "$UNIQUE_ORIGIN_POOLS" ]; then
            echo "   📋 Origin pools to be configured:"
            echo "$BASE_ORIGIN_POOLS" | while read -r pool; do
                if [ -n "$pool" ]; then
                    echo "      - $pool"
                fi
            done

            echo ""
            echo "🔍 Generated unique origin pool names from Terraform:"
            echo "$UNIQUE_ORIGIN_POOLS" | tr ' ' '\n' | grep -v '^$' | while read -r pool; do
                echo "      - $pool"
            done

            echo ""
            echo "🔍 Checking F5 XC API if these origin pools already exist..."

            # Check each unique origin pool against the F5 XC API
            EXISTING_POOLS=""
            for pool in $UNIQUE_ORIGIN_POOLS; do
                if [ -n "$pool" ]; then
                    echo "   Checking if origin pool '$pool' already exists..."

                    # Use kubectl proxy to access F5 XC API
                    # Based on F5 XC API documentation: https://docs.cloud.f5.com/docs-v2/api/views-origin-pool
                    # The correct endpoint follows the F5 XC API pattern, not Kubernetes API pattern
                    # 
                    # F5 XC Origin Pool API endpoints:
                    # - List: GET /api/web/namespaces/{namespace}/origin_pools
                    # - Get: GET /api/web/namespaces/{namespace}/origin_pools/{name}
                    # 
                    # Using the kubectl proxy to access the F5 XC API through the cluster
                    # Dynamically use the namespace from Terraform output instead of hardcoding
                    # Check if unique origin pool exists (only need HTTP status, not full response)
                    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8001/api/config/namespaces/$NAMESPACE/origin_pools/$pool" 2>/dev/null || echo "000")

                    if [ "$HTTP_STATUS" = "200" ]; then
                        echo "      ⚠️  Unique origin pool '$pool' already exists!"
                        EXISTING_POOLS="$EXISTING_POOLS $pool"
                    elif [ "$HTTP_STATUS" = "404" ]; then
                        echo "      ✅ Unique origin pool '$pool' does not exist (ready to create)"
                    else
                        echo "      ❓ Unable to determine status for '$pool' (HTTP: $HTTP_STATUS)"
                    fi
                fi
            done
        
        echo ""
        if [ -n "$EXISTING_POOLS" ]; then
            echo "❌ ERROR: The following unique origin pools already exist in F5 XC:"
            echo "$EXISTING_POOLS" | tr ' ' '\n' | grep -v '^$' | while read -r pool; do
                echo "      - $pool"
            done
            echo ""
            echo "   Deployment failed: Unique origin pool conflicts detected."
            echo "   This is unexpected - please check your F5 XC configuration."
            echo "   You may need to delete existing pools or regenerate unique names by running terraform destroy and terraform apply again."
            exit 1
        else
            echo "✅ All unique origin pools are ready to be created in F5 XC."
            echo "   Proceeding with Kubernetes deployment..."
        fi
    else
        echo "   ℹ️  No origin pools detected in Terraform output"
    fi

    # Create origin pools using F5 XC API
    echo "🏗️  Creating F5 XC origin pools via API..."
    
    # Check if origin pool configuration files exist
    ORIGIN_POOLS_DIR="outputs/envoy/f5xc"
    if [ ! -d "$ORIGIN_POOLS_DIR" ]; then
        echo "   ❌ Origin pools directory not found: $ORIGIN_POOLS_DIR"
        echo "      Please run 'terraform apply' first to generate the origin pool configurations"
        exit 1
    fi
    
    # Wait a moment for Kubernetes service to be fully ready
    echo "   ⏳ Waiting for Kubernetes service to be ready..."
    sleep 5
    
    # Get the origin pool configuration from Terraform output
    if command -v jq &> /dev/null; then
        ORIGIN_POOL_CONFIG=$(terraform output -json f5xc_origin_pools 2>/dev/null)
        
        # Verify that all required JSON files exist
        MISSING_FILES=""
        for pool_config in $(echo "$ORIGIN_POOL_CONFIG" | jq -c '.[]'); do
            UNIQUE_POOL_NAME=$(echo "$pool_config" | jq -r '.f5xc_origin_pool_unique')
            JSON_FILE="$ORIGIN_POOLS_DIR/$UNIQUE_POOL_NAME.json"
            if [ ! -f "$JSON_FILE" ]; then
                MISSING_FILES="$MISSING_FILES $JSON_FILE"
            fi
        done
        
        if [ -n "$MISSING_FILES" ]; then
            echo "   ❌ Missing origin pool JSON configuration files:"
            echo "$MISSING_FILES" | tr ' ' '\n' | grep -v '^$' | while read -r file; do
                echo "      - $file"
            done
            echo "      Please run 'terraform apply' first to generate all required files"
            exit 1
        fi
        
        echo "   ✅ All origin pool JSON configuration files are available"
    else
        echo "   ⚠️  jq not found, cannot create origin pools automatically"
        echo "   Please create origin pools manually in F5 XC console or use jq for automation"
        ORIGIN_POOL_CONFIG=""
    fi
    
    if [ -n "$ORIGIN_POOL_CONFIG" ]; then
        # Create each origin pool
        CREATED_POOLS=""
        FAILED_POOLS=""
        
        # Parse the JSON and create pools
        echo "$ORIGIN_POOL_CONFIG" | jq -c '.[]' | while read -r pool_config; do
            if [ -n "$pool_config" ]; then
                # Extract pool details
                BASE_POOL_NAME=$(echo "$pool_config" | jq -r '.f5xc_origin_pool')
                SERVICE_ENDPOINT=$(echo "$pool_config" | jq -r '.service_endpoint')
                EXPOSED_PORT=$(echo "$pool_config" | jq -r '.exposed_port')
                ENDPOINT=$(echo "$pool_config" | jq -r '.endpoint')
                TAILNET_NAME=$(echo "$pool_config" | jq -r '.tailnet_name')
                
                # Get the unique pool name from Terraform output
                UNIQUE_POOL_NAME=$(echo "$ORIGIN_POOL_CONFIG" | jq -r --arg base_name "$BASE_POOL_NAME" '.[] | select(.f5xc_origin_pool == $base_name) | .f5xc_origin_pool_unique' 2>/dev/null || echo "")
                
                if [ -n "$UNIQUE_POOL_NAME" ]; then
                    echo "   🏗️  Creating origin pool: $UNIQUE_POOL_NAME"
                    echo "      📍 Backend: $SERVICE_ENDPOINT"
                    echo "      🔌 Port: $EXPOSED_PORT"
                    echo "      🎯 Service: $ENDPOINT"
                    echo "      🌐 Tailnet: $TAILNET_NAME"
                    
                    # Read the origin pool configuration JSON from Terraform-generated file
                    ORIGIN_POOL_JSON_FILE="outputs/envoy/f5xc/$UNIQUE_POOL_NAME.json"
                    
                    if [ -f "$ORIGIN_POOL_JSON_FILE" ]; then
                        ORIGIN_POOL_JSON=$(cat "$ORIGIN_POOL_JSON_FILE")
                        echo "      📁 Using JSON configuration from: $ORIGIN_POOL_JSON_FILE"
                    else
                        echo "      ❌ JSON configuration file not found: $ORIGIN_POOL_JSON_FILE"
                        echo "         Please run 'terraform apply' first to generate the origin pool configurations"
                        FAILED_POOLS="$FAILED_POOLS $UNIQUE_POOL_NAME"
                        continue
                    fi
                    
                    # Create the origin pool via F5 XC API
                    echo "      📤 Sending creation request to F5 XC API..."
                    
                    # Use kubectl proxy to access F5 XC API
                    # POST to create new origin pool using the correct F5 XC API endpoint
                    # Based on: https://docs.cloud.f5.com/docs-v2/api/views-origin-pool#operation/ves.io.schema.views.origin_pool.API.Create
                    # Try different API endpoint variations for F5 XC
                    HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
                        -H "Content-Type: application/json" \
                        -d "$ORIGIN_POOL_JSON" \
                        "http://localhost:8001/api/config/namespaces/$NAMESPACE/origin_pools" \
                        2>/dev/null)
                    
                    # Extract HTTP status code (last line) and response body
                    # Use a simple approach: split by newline and get last element
                    HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr '\n' ' ' | awk '{print $NF}')
                    # Get all lines except the last one (HTTP status)
                    RESPONSE_BODY=$(echo "$HTTP_RESPONSE" | sed '$d')
                    
                    if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "201" ]; then
                        echo "      ✅ Origin pool '$UNIQUE_POOL_NAME' created successfully"
                        CREATED_POOLS="$CREATED_POOLS $UNIQUE_POOL_NAME"
                    else
                        echo "      ❌ Failed to create origin pool '$UNIQUE_POOL_NAME'"
                        echo "         HTTP Status: $HTTP_STATUS"
                        echo "         Response: $RESPONSE_BODY"
                        FAILED_POOLS="$FAILED_POOLS $UNIQUE_POOL_NAME"
                    fi
                    
                    echo ""
                else
                    echo "   ⚠️  Could not find unique name for base pool: $BASE_POOL_NAME"
                    FAILED_POOLS="$FAILED_POOLS $BASE_POOL_NAME"
                fi
            fi
        done
        
        echo ""
        if [ -n "$CREATED_POOLS" ]; then
            echo "✅ Successfully created origin pools:"
            echo "$CREATED_POOLS" | tr ' ' '\n' | grep -v '^$' | while read -r pool; do
                echo "      - $pool"
            done
        fi
        
        if [ -n "$FAILED_POOLS" ]; then
            echo "❌ Failed to create origin pools:"
            echo "$FAILED_POOLS" | tr ' ' '\n' | grep -v '^$' | while read -r pool; do
                echo "      - $pool"
            done
            echo ""
            echo "   ⚠️  Some origin pools failed to create. Check the errors above."
            echo "   You may need to create them manually in the F5 XC console."
        fi
        
        if [ -z "$FAILED_POOLS" ]; then
            echo "🎉 All origin pools created successfully in F5 XC!"
        fi
    else
        echo "   ℹ️  No origin pool configuration available for automatic creation"
    fi
    
    echo ""
    
    # Apply manifests in order
    for manifest in outputs/envoy/k8s/*.yaml; do
        if [ -f "$manifest" ]; then
            echo "  Applying $(basename "$manifest")..."
            kubectl apply -f "$manifest" -n "$NAMESPACE"
        fi
    done
    
    echo "✅ Kubernetes manifests applied successfully"
    
    # Stop kubectl proxy since it's no longer needed
    echo "🛑 Stopping kubectl proxy..."
    
    # Method 1: Try to stop using PID file
    if [ -f ".kubectl-proxy.pid" ]; then
        PROXY_PID=$(cat .kubectl-proxy.pid)
        if kill -0 "$PROXY_PID" 2>/dev/null; then
            echo "   🎯 Stopping kubectl proxy with PID: $PROXY_PID"
            kill "$PROXY_PID"
            
            # Wait a moment for graceful shutdown
            sleep 2
            
            # Check if it's still running
            if kill -0 "$PROXY_PID" 2>/dev/null; then
                echo "   ⚠️  Graceful shutdown failed, forcing termination..."
                kill -9 "$PROXY_PID" 2>/dev/null || true
            fi
            
            echo "   ✅ kubectl proxy (PID: $PROXY_PID) stopped successfully"
        else
            echo "   ℹ️  kubectl proxy process already stopped"
        fi
        rm -f .kubectl-proxy.pid
    else
        echo "   ℹ️  No kubectl proxy PID file found"
    fi
    
    # Method 2: Fallback - kill any remaining kubectl proxy processes
    REMAINING_PROXIES=$(pgrep -f "kubectl proxy --port=8001" 2>/dev/null || true)
    if [ -n "$REMAINING_PROXIES" ]; then
        echo "   🧹 Cleaning up remaining kubectl proxy processes..."
        echo "$REMAINING_PROXIES" | while read -r pid; do
            if [ -n "$pid" ]; then
                echo "      Stopping PID: $pid"
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
        echo "   ✅ All remaining kubectl proxy processes stopped"
    fi
    
    # Method 3: Check if port 8001 is still in use
    if command -v lsof &> /dev/null; then
        PORT_USERS=$(lsof -ti:8001 2>/dev/null || true)
        if [ -n "$PORT_USERS" ]; then
            echo "   🚨 Port 8001 still in use by processes: $PORT_USERS"
            echo "      You may need to manually stop these processes"
        else
            echo "   ✅ Port 8001 is now free"
        fi
    fi
    
    echo ""
    
    # Show deployment status
    echo "📊 Checking deployment status..."
    kubectl get statefulset tailscale-egress -n "$NAMESPACE" -o wide 2>/dev/null || echo "StatefulSet not found yet..."
    kubectl get service tailscale-egress -n "$NAMESPACE" -o wide 2>/dev/null || echo "Service not found yet..."
    
    echo ""
    echo "🎉 Deployment completed successfully!"
    echo ""
    echo "📖 Next steps:"
    echo "  - Check pod status: kubectl get pods -l app=tailscale-egress -n $NAMESPACE"
    echo "  - View logs: kubectl logs -l app=tailscale-egress -c tailscale-<tailnet-name> -n $NAMESPACE"
    echo "  - Port forward for testing: kubectl port-forward svc/tailscale-egress <local-port>:<service-port> -n $NAMESPACE"
    echo ""
    echo "📚 For more information, see configuration-summary.md generated by Terraform in the outputs/$PROXY_TYPE directory"
else
    echo "⚠️  No manifests found for $PROXY_TYPE. Run 'terraform apply' first to generate Kubernetes manifests."
fi
