#!/bin/bash

# F5 XC Tailnet Egress Deployment Script

set -e

# Parse command line arguments
VERBOSE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --verbose    Show verbose Terraform output"
            echo "  -h, --help   Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0              # Run with minimal output (default)"
            echo "  $0 --verbose    # Run with verbose Terraform output"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Configuration
PROXY_TYPE=${PROXY_TYPE:-"envoy"}
NAMESPACE=""
PROXY_PID=""

# Enhanced color palette
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
NC='\033[0m' # No Color

# Background colors
BG_BLUE='\033[44m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_RED='\033[41m'

# ASCII Art
BANNER="
${BOLD}${CYAN}🚀 F5 XC Tailnet Egress Deployment${NC}
"





# Enhanced logging functions
log_header() { 
    echo -e "\n${BOLD}${BG_BLUE}${WHITE} $1 ${NC}\n"
}

log_step() { 
    echo -e "${CYAN}🔧${NC} ${BOLD}$1${NC}"
}

log_info() { 
    echo -e "${BLUE}ℹ️  ${NC}$1"
}

log_success() { 
    echo -e "${GREEN}✅ ${NC}${BOLD}$1${NC}"
}

log_warning() { 
    echo -e "${YELLOW}⚠️  ${NC}$1"
}

log_error() { 
    echo -e "${RED}❌ ${NC}${BOLD}$1${NC}"
}

log_progress() {
    echo -e "${PURPLE}🔄 ${NC}$1"
}

log_complete() {
    echo -e "${GREEN}🎯 ${NC}${BOLD}$1${NC}"
}

# Fancy separator
show_separator() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Cleanup function
cleanup() {
    if [ -n "$PROXY_PID" ] && kill -0 "$PROXY_PID" 2>/dev/null; then
        log_progress "Stopping kubectl proxy (PID: $PROXY_PID)..."
        kill "$PROXY_PID" 2>/dev/null || true
        sleep 1
        if kill -0 "$PROXY_PID" 2>/dev/null; then
            kill -9 "$PROXY_PID" 2>/dev/null || true
        fi
    fi
    
    # Clean up any remaining proxy processes
    pkill -f "kubectl proxy --port=8001" 2>/dev/null || true
    rm -f .kubectl-proxy.pid
}

# Check prerequisites
check_prerequisites() {
    log_header "PREREQUISITES CHECK"
    
    local tools=("terraform" "kubectl" "curl")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        log_progress "Checking $tool..."
        
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    if [ ! -f "terraform.tfvars" ]; then
        log_error "terraform.tfvars not found. Please configure it first."
        exit 1
    fi
    

    
    log_success "All prerequisites satisfied"
    show_separator
}

# Terraform operations
run_terraform() {
    log_header "TERRAFORM DEPLOYMENT"
    
    log_step "Initializing Terraform..."
    if [ "$VERBOSE" = true ]; then
        terraform init
    else
        terraform init -compact-warnings > /dev/null 2>&1
    fi
    log_success "init completed"
    
    log_step "Validating configuration..."
    if [ "$VERBOSE" = true ]; then
        terraform validate
    else
        terraform validate -compact-warnings > /dev/null 2>&1
    fi
    log_success "validate completed"
    
    log_step "Applying Terraform configuration..."
    if [ "$VERBOSE" = true ]; then
        terraform apply --auto-approve
    else
        terraform apply --auto-approve -compact-warnings > /dev/null 2>&1
    fi
    log_success "Terraform deployment complete"
    show_separator
}

# Start kubectl proxy
start_proxy() {
    log_header "KUBERNETES CONNECTION"
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    NAMESPACE=$(terraform output -raw k8s_namespace 2>/dev/null || echo "default")
    log_info "Target namespace: ${BOLD}$NAMESPACE${NC}"
    
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_error "Namespace '$NAMESPACE' does not exist"
        exit 1
    fi
    
    log_step "Starting kubectl proxy..."
    kubectl proxy > /dev/null 2>&1 &
    PROXY_PID=$!
    sleep 2
    
    if kill -0 "$PROXY_PID" 2>/dev/null; then
        echo "$PROXY_PID" > .kubectl-proxy.pid
        log_success "kubectl proxy active (PID: $PROXY_PID)"
    else
        log_error "Failed to start kubectl proxy"
        show_troubleshooting_tips
        exit 1
    fi
    show_separator
}



# Create origin pools
create_origin_pools() {
    log_header "F5 XC OBJECT CREATION"
    
    local pools_dir="outputs/envoy/f5xc"
    

    
    local created=0
    
    log_progress "Creating origin pools..."
    
    # Find all JSON files in the pools directory
    local json_files=($pools_dir/*.json)
    
    if [ ${#json_files[@]} -eq 0 ]; then
        log_error "No JSON files found in $pools_dir"
        log_error "Check Terraform outputs and ensure origin pool configuration files are generated"
        show_troubleshooting_tips
        exit 1
    fi
    
    for json_file in "${json_files[@]}"; do
        if [ -f "$json_file" ]; then
            # Extract the origin pool name from the filename (without .json extension)
            local unique_name=$(basename "$json_file" .json)
            
            log_info "Creating: ${BOLD}$unique_name${NC}"
            
            local response=$(curl -s -w "\n%{http_code}" -X POST \
                -H "Content-Type: application/json" \
                -d "$(cat "$json_file")" \
                "http://localhost:8001/api/config/namespaces/$NAMESPACE/origin_pools" \
                2>/dev/null)
            
            local status=$(echo "$response" | tail -n1)
            if [ "$status" = "200" ] || [ "$status" = "201" ]; then
                log_success "Created: $unique_name"
                ((created++))
            else
                log_error "Failed: $unique_name (HTTP: $status)"
                log_error "💡 Investigate error response codes at: https://docs.cloud.f5.com/docs-v2/api/views-origin-pool#operation/ves.io.schema.views.origin_pool.API.Create"
                log_error "Stopping deployment due to origin pool creation failure"
                show_troubleshooting_tips
                exit 1
            fi
        fi
    done
    
    log_success "All origin pools created successfully"
    show_separator
}

# Apply Kubernetes manifests
apply_manifests() {
    log_header "KUBERNETES DEPLOYMENT"
    
    local manifests_dir="outputs/envoy/k8s"
    local manifest_files=($manifests_dir/*.yaml)
    
    log_progress "Applying Kubernetes manifests..."
    
    for manifest in "${manifest_files[@]}"; do
        if [ -f "$manifest" ]; then
            local basename=$(basename "$manifest")
            log_info "Applying: ${BOLD}$basename${NC}"
            
            kubectl apply -f "$manifest" -n "$NAMESPACE"
        fi
    done
    
    log_success "All Kubernetes manifests applied"
    show_separator
}

# Show troubleshooting tips
show_troubleshooting_tips() {
    log_header "TROUBLESHOOTING TIPS"
    
    echo -e "${BOLD}${YELLOW}🔧 Common Issues & Solutions:${NC}\n"
    
    echo -e "${BOLD}${CYAN}F5 XC OBJECT CREATION:${NC}"
    echo -e "  • Most errors occur when trying to create objects that already exist"
    echo -e "  • Solution: Run ${BOLD}terraform destroy${NC} to clean up existing resources"
    echo -e "  • Then retry: ${BOLD}./deploy.sh${NC}\n"

    echo -e "${BOLD}${CYAN}KUBERNETES CONNECTION:${NC}"
    echo -e "  • Ensure kubeconfig is valid and not expired"
    echo -e "  • Check kubectl connection and verify cluster access"
    echo -e "  • Verify: ${BOLD}kubectl cluster-info${NC}"
    echo -e "  • kubectl proxy default listen port is 8001, make sure it is not in use\n"

    echo -e "${BOLD}${WHITE}📚 Additional Resources:${NC}"
    echo -e "  • Terraform Commands: ${BOLD}terraform plan${NC}, ${BOLD}terraform apply${NC}, ${BOLD}terraform destroy${NC}"
    
    show_separator
}

# Show deployment status
show_status() {
    log_header "DEPLOYMENT STATUS"
    
    log_progress "Checking resource status..."
    
    echo -e "\n${BOLD}${CYAN}StatefulSet:${NC}"
    kubectl get statefulset tailscale-egress -n "$NAMESPACE" -o wide 2>/dev/null || log_info "StatefulSet not found yet..."
    
    echo -e "\n${BOLD}${CYAN}Service:${NC}"
    kubectl get service tailscale-egress -n "$NAMESPACE" -o wide 2>/dev/null || log_info "Service not found yet..."
    
    echo -e "\n${BOLD}${GREEN}🎉 DEPLOYMENT SUCCESSFUL! ✨ All systems operational${NC}\n"
    
    echo -e "${BOLD}${WHITE}Next Steps:${NC}"
    echo -e "  ${CYAN}📊${NC} Check pod status: ${BOLD}kubectl get pods -l app=tailscale-egress -n $NAMESPACE${NC}"
    echo -e "  ${CYAN}📋${NC} View logs: ${BOLD}kubectl logs -l app=tailscale-egress -c tailscale-<tailnet-name> -n $NAMESPACE${NC}"
    echo -e "  ${CYAN}🔗${NC} Port forward: ${BOLD}kubectl port-forward svc/tailscale-egress <local-port>:<service-port> -n $NAMESPACE${NC}"
    
    show_separator
}

# Main execution
main() {
    clear
    echo -e "$BANNER"
    echo -e "${BOLD}${WHITE}Proxy Type:${NC} ${CYAN}$PROXY_TYPE${NC}"
    echo -e "${BOLD}${WHITE}Timestamp:${NC} ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    show_separator
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    check_prerequisites
    run_terraform
    
    echo -e "\n${BOLD}${YELLOW}🤔 Ready to press the red button? 🚨${NC}"
    echo -e "${BOLD}${WHITE}💡 Review the configuration summary:${NC} ${CYAN}outputs/envoy/configuration-summary.md${NC}"
    read -p "   Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment stopped after Terraform. Review configuration-summary.md and run ./deploy.sh again when ready."
        exit 0
    fi
    
    if [ "$PROXY_TYPE" = "envoy" ]; then
        start_proxy
        create_origin_pools
        apply_manifests
        show_status
    else
        log_info "Proxy type '$PROXY_TYPE' not yet implemented"
    fi
}

# Run main function
main "$@"

