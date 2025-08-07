#!/bin/bash

# Cloud-Native Infrastructure Deployment Script - OPTIMIZED VERSION
# Addresses code smells and performance issues from original script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PID_FILE="$SCRIPT_DIR/.admin-port-forward.pid"

# Configuration - now parameterized
readonly CROSSPLANE_NAMESPACE="${CROSSPLANE_NAMESPACE:-crossplane-system}"
readonly LOCALSTACK_NAMESPACE="${LOCALSTACK_NAMESPACE:-localstack}"
readonly AWS_REGION="${AWS_REGION:-eu-central-1}"
readonly TIMEOUT="${TIMEOUT:-300s}"
readonly PARALLEL_JOBS="${PARALLEL_JOBS:-3}"

# Colors
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

print_info() { echo -e "${BLUE}  $1${NC}"; }
print_success() { echo -e "${GREEN} $1${NC}"; }
print_warning() { echo -e "${YELLOW} $1${NC}"; }
print_error() { echo -e "${RED} $1${NC}"; }

# Enhanced error handling
handle_error() {
    local line_no=$1
    local error_code=$2
    print_error "Error on line $line_no: Command exited with status $error_code"
    cleanup_on_error
    exit $error_code
}

trap 'handle_error $LINENO $?' ERR

cleanup_on_error() {
    print_warning "Cleaning up due to error..."
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
}

echo "Deploying Cloud-Native Event-Driven Architecture (Optimized)"
echo "============================================================"
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Optimized prerequisites validation with parallel checks
validate_prerequisites() {
    print_info "=== Prerequisites Validation ==="
    
    local tools=("kubectl" "helm" "docker" "curl")
    local failed_tools=()
    
    # Check tools in parallel
    for tool in "${tools[@]}"; do
        {
            if ! command -v "$tool" >/dev/null 2>&1; then
                echo "$tool" >> /tmp/failed_tools.$$
            fi
        } &
    done
    wait
    
    # Check for failures
    if [[ -f /tmp/failed_tools.$$ ]]; then
        while read -r tool; do
            failed_tools+=("$tool")
        done < /tmp/failed_tools.$$
        rm -f /tmp/failed_tools.$$
        
        print_error "Missing tools: ${failed_tools[*]}"
        exit 1
    fi
    
    # Check Kubernetes connection
    if ! kubectl cluster-info --request-timeout=10s >/dev/null 2>&1; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    print_success "Prerequisites validated"
}

# Optimized Crossplane installation with better condition checking
install_crossplane() {
    print_info "=== Crossplane Installation ==="
    
    # Only add repo if not already present
    if ! helm repo list | grep -q crossplane-stable; then
        helm repo add crossplane-stable https://charts.crossplane.io/stable
    fi
    helm repo update crossplane-stable
    
    # Check if already installed and ready
    if kubectl get deployment crossplane -n $CROSSPLANE_NAMESPACE >/dev/null 2>&1; then
        if kubectl wait --for=condition=available deployment/crossplane \
           -n $CROSSPLANE_NAMESPACE --timeout=10s >/dev/null 2>&1; then
            print_success "Crossplane already installed and ready"
            return 0
        fi
        print_info "Crossplane installed but not ready, upgrading..."
        helm upgrade crossplane crossplane-stable/crossplane \
            --namespace $CROSSPLANE_NAMESPACE \
            --wait --timeout=$TIMEOUT
    else
        print_info "Installing Crossplane..."
        helm install crossplane crossplane-stable/crossplane \
            --namespace $CROSSPLANE_NAMESPACE \
            --create-namespace \
            --wait --timeout=$TIMEOUT
    fi
    
    print_success "Crossplane installation completed"
}

# Optimized AWS provider installation with proper waiting
install_aws_provider() {
    print_info "=== AWS Provider Installation ==="
    
    # Apply configurations
    kubectl apply -f "$PROJECT_ROOT/crossplane/deployment-runtime-config.yaml"
    kubectl apply -f "$PROJECT_ROOT/crossplane/provider.yaml"
    
    # Wait for provider to be healthy instead of arbitrary sleep
    print_info "Waiting for AWS provider to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if kubectl get provider.pkg.crossplane.io/provider-aws -o jsonpath='{.status.conditions[?(@.type=="Healthy")].status}' 2>/dev/null | grep -q "True"; then
            print_success "AWS Provider is healthy"
            return 0
        fi
        sleep 10
        ((attempt++))
        print_info "Attempt $attempt/$max_attempts - Provider not ready yet..."
    done
    
    print_warning "Provider may not be fully ready, continuing..."
}

# Parallel LocalStack deployment
deploy_localstack() {
    print_info "=== LocalStack Deployment ==="
    
    # Create namespace and deploy in parallel
    {
        kubectl create namespace $LOCALSTACK_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    } &
    {
        kubectl apply -f "$PROJECT_ROOT/k8s/localstack.yaml"
    } &
    wait
    
    # Wait for LocalStack with proper condition
    print_info "Waiting for LocalStack to be ready..."
    kubectl wait --for=condition=available deployment/localstack \
        -n $LOCALSTACK_NAMESPACE --timeout=$TIMEOUT
    
    # Health check instead of arbitrary sleep
    local max_attempts=12
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if kubectl exec -n $LOCALSTACK_NAMESPACE deployment/localstack -- curl -s http://localhost:4566/_localstack/health >/dev/null 2>&1; then
            print_success "LocalStack is healthy and ready"
            return 0
        fi
        sleep 5
        ((attempt++))
    done
    
    print_warning "LocalStack health check timeout, continuing..."
}

create_provider_config() {
    print_info "=== Provider Configuration ==="
    kubectl apply -f "$PROJECT_ROOT/crossplane/provider-config.yaml"
    print_success "Provider configuration completed"
}

# Optimized AWS resources creation with parallel processing
create_aws_resources() {
    print_info "=== AWS Resources Creation ==="
    
    local resources=("sns-topic" "sqs-queue" "dynamodb-table")
    local pids=()
    
    # Create independent resources in parallel
    for resource in "${resources[@]}"; do
        {
            print_info "Creating $resource..."
            kubectl apply -f "$PROJECT_ROOT/crossplane/${resource}.yaml"
        } &
        pids+=($!)
    done
    
    # Wait for all parallel jobs
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    # Create SNS subscription after topic is ready
    print_info "Creating sns-subscription..."
    kubectl apply -f "$PROJECT_ROOT/crossplane/sns-subscription.yaml"
    
    # Wait for resources to be ready with proper conditions
    print_info "Waiting for AWS resources to be ready..."
    local resources_ready=0
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts && $resources_ready -lt 4 ]]; do
        resources_ready=0
        
        # Check each resource status
        for resource_type in "topic" "queue" "table" "subscription"; do
            if kubectl get "$resource_type" -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
                ((resources_ready++))
            fi
        done
        
        if [[ $resources_ready -eq 4 ]]; then
            break
        fi
        
        sleep 10
        ((attempt++))
        print_info "Attempt $attempt/$max_attempts - $resources_ready/4 resources ready"
    done
    
    print_success "AWS infrastructure provisioned successfully ($resources_ready/4 resources ready)"
}

# Parallel application deployment
deploy_applications() {
    print_info "=== Applications Deployment ==="
    
    local apps=("producer" "consumer" "dynamodb-admin")
    local pids=()
    
    # Deploy applications in parallel
    {
        print_info "Installing producer..."
        helm upgrade --install producer "$PROJECT_ROOT/helm/producer" \
            --set image.repository=ghcr.io/justtrackio/devopstest-producer \
            --set image.tag=latest \
            --set env.CLOUD_AWS_DEFAULTS_ENDPOINT=http://localstack.localstack.svc.cluster.local:4566 \
            --wait --timeout=$TIMEOUT
    } &
    pids+=($!)
    
    {
        print_info "Installing consumer..."
        helm upgrade --install consumer "$PROJECT_ROOT/helm/consumer" \
            --set image.repository=ghcr.io/justtrackio/devopstest-consumer \
            --set image.tag=latest \
            --set env.CLOUD_AWS_DEFAULTS_ENDPOINT=http://localstack.localstack.svc.cluster.local:4566 \
            --wait --timeout=$TIMEOUT
    } &
    pids+=($!)
    
    {
        print_info "Installing dynamodb-admin..."
        helm upgrade --install dynamodb-admin "$PROJECT_ROOT/helm/dynamodb-admin" \
            --set env.DYNAMO_ENDPOINT=http://localstack.localstack.svc.cluster.local:4566 \
            --set env.AWS_REGION=$AWS_REGION \
            --wait --timeout=$TIMEOUT
    } &
    pids+=($!)
    
    # Wait for all deployments
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    print_success "All applications deployed successfully"
}

# Optimized admin interface startup with better error handling
start_admin_interface() {
    print_info "=== Starting DynamoDB Admin Interface ==="
    
    # Check if already running
    if [[ -f "$PID_FILE" ]]; then
        local old_pid
        old_pid=$(cat "$PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            print_warning "Admin interface already running (PID: $old_pid)"
            print_info "Access at: http://localhost:8001"
            return 0
        else
            rm -f "$PID_FILE"
        fi
    fi
    
    # Verify service exists
    if ! kubectl get svc dynamodb-admin-dynamodb-admin >/dev/null 2>&1; then
        print_error "DynamoDB Admin service not found"
        return 1
    fi
    
    # Start port-forward
    print_info "Starting port-forward..."
    kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8001:8001 >/dev/null 2>&1 &
    local port_forward_pid=$!
    echo "$port_forward_pid" > "$PID_FILE"
    
    # Wait for service to be ready with proper health check
    local max_attempts=10
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -s --connect-timeout 2 http://localhost:8001 >/dev/null 2>&1; then
            print_success "DynamoDB Admin interface started successfully!"
            print_info "URL: http://localhost:8001"
            print_info "Table: justtrack-dev-devops-consumer-events"
            print_info "PID: $port_forward_pid"
            
            # Optional browser opening
            if command -v open >/dev/null 2>&1; then
                echo ""
                echo -n "Open DynamoDB Admin interface in browser? (Y/n): "
                read -r response
                case "$response" in
                    [nN]|[nN][oO])
                        print_info "Browser not opened. Access manually at: http://localhost:8001"
                        ;;
                    *)
                        print_info "Opening browser..."
                        open http://localhost:8001
                        ;;
                esac
            fi
            return 0
        fi
        
        sleep 2
        ((attempt++))
    done
    
    print_error "Failed to start admin interface"
    kill "$port_forward_pid" 2>/dev/null || true
    rm -f "$PID_FILE"
    return 1
}

# Enhanced verification with parallel checks
verify_deployment() {
    print_info "=== Deployment Verification ==="
    
    {
        print_info "Checking pod status..."
        kubectl get pods --all-namespaces | grep -E "(crossplane|localstack|producer|consumer|dynamodb)" || true
    } &
    
    {
        print_info "Checking Helm releases..."
        helm list
    } &
    
    wait
    print_success "Deployment verification completed"
}

stop_admin_interface() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            print_info "Admin interface stopped (PID: $pid)"
        fi
        rm -f "$PID_FILE"
    fi
}

# Main deployment function with timing
main() {
    local start_time
    start_time=$(date +%s)
    
    validate_prerequisites
    install_crossplane
    install_aws_provider
    deploy_localstack
    create_provider_config
    create_aws_resources
    deploy_applications
    verify_deployment
    start_admin_interface
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo "OPTIMIZED DEPLOYMENT COMPLETED!"
    echo "==============================="
    echo ""
    echo "Deployment Summary:"
    echo "  • Duration: ${duration}s"
    echo "  • AWS Resources: 4 created (SNS, SQS, DynamoDB, Subscription)"
    echo "  • Applications: 3 deployed (Producer, Consumer, DynamoDB Admin)"
    echo "  • LocalStack: Running and configured"
    echo "  • Admin Interface: Started and accessible"
    echo ""
    echo "DynamoDB Admin Interface:"
    echo "  • URL: http://localhost:8001"
    echo "  • Table: justtrack-dev-devops-consumer-events"
    echo ""
    echo "Monitor the event flow:"
    echo "  • Producer logs: kubectl logs -l app=producer-producer -f"
    echo "  • Consumer logs: kubectl logs -l app=consumer-consumer -f"
    echo ""
    echo "Additional commands:"
    echo "  • Run tests: ./test.sh"
    echo "  • Stop admin interface: kill \$(cat $PID_FILE)"
    echo "  • Full cleanup: ./cleanup.sh"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--help|--stop-admin]"
        echo "Deploys the complete cloud-native event-driven architecture (optimized version)"
        echo ""
        echo "Environment Variables:"
        echo "  CROSSPLANE_NAMESPACE  Crossplane namespace (default: crossplane-system)"
        echo "  LOCALSTACK_NAMESPACE  LocalStack namespace (default: localstack)"
        echo "  AWS_REGION           AWS region (default: eu-central-1)"
        echo "  TIMEOUT              Helm timeout (default: 300s)"
        echo "  PARALLEL_JOBS        Max parallel jobs (default: 3)"
        echo ""
        echo "Options:"
        echo "  --help        Show this help message"
        echo "  --stop-admin  Stop only the admin interface"
        exit 0
        ;;
    --stop-admin)
        echo "Stopping DynamoDB Admin Interface"
        echo "=================================="
        stop_admin_interface
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
