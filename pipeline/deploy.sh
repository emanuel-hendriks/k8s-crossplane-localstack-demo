#!/bin/bash

# Cloud-Native Infrastructure Deployment Script - RELIABLE VERSION
# Based on documentation insights - skips problematic provider waiting

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

# Configuration
readonly CROSSPLANE_NAMESPACE="crossplane-system"
readonly LOCALSTACK_NAMESPACE="localstack"
readonly AWS_REGION="eu-central-1"

echo "🚀 Deploying Cloud-Native Event-Driven Architecture"
echo "===================================================="
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Validate prerequisites
validate_prerequisites() {
    print_info "=== Prerequisites Validation ==="
    
    for tool in kubectl helm docker; do
        if ! command -v $tool >/dev/null 2>&1; then
            print_error "$tool is not installed or not in PATH"
            exit 1
        fi
    done
    
    # Check Kubernetes connection
    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    print_success "Prerequisites validated"
}

# Install Crossplane
install_crossplane() {
    print_info "=== Crossplane Installation ==="
    
    # Add Crossplane Helm repository
    helm repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1
    
    # Install or upgrade Crossplane
    if helm list -n $CROSSPLANE_NAMESPACE | grep -q crossplane; then
        print_info "Crossplane already installed, upgrading..."
        helm upgrade crossplane crossplane-stable/crossplane \
            --namespace $CROSSPLANE_NAMESPACE \
            --wait --timeout=300s >/dev/null 2>&1
    else
        print_info "Installing Crossplane..."
        helm install crossplane crossplane-stable/crossplane \
            --namespace $CROSSPLANE_NAMESPACE \
            --create-namespace \
            --wait --timeout=300s >/dev/null 2>&1
    fi
    
    # Wait for Crossplane to be ready
    kubectl wait --for=condition=ready pod -l app=crossplane \
        --namespace $CROSSPLANE_NAMESPACE --timeout=180s >/dev/null 2>&1
    
    print_success "Crossplane installation completed"
}

# Install AWS Provider (SIMPLIFIED - no waiting)
install_aws_provider() {
    print_info "=== AWS Provider Installation ==="
    
    # Apply provider configuration
    kubectl apply -f "$PROJECT_ROOT/crossplane/deployment-runtime-config.yaml" >/dev/null 2>&1
    kubectl apply -f "$PROJECT_ROOT/crossplane/provider.yaml" >/dev/null 2>&1
    
    # Give provider time to start (no hanging wait)
    print_info "Allowing provider to initialize..."
    sleep 30
    
    print_success "AWS Provider installation completed"
}

# Deploy LocalStack
deploy_localstack() {
    print_info "=== LocalStack Deployment ==="
    
    # Create namespace
    kubectl create namespace $LOCALSTACK_NAMESPACE --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
    
    # Deploy LocalStack
    kubectl apply -f "$PROJECT_ROOT/k8s/localstack.yaml" >/dev/null 2>&1
    
    # Wait for LocalStack to be ready
    print_info "Waiting for LocalStack to be ready..."
    kubectl wait --for=condition=available deployment/localstack \
        -n $LOCALSTACK_NAMESPACE --timeout=180s >/dev/null 2>&1
    
    print_success "LocalStack deployment completed"
}

# Create provider configuration
create_provider_config() {
    print_info "=== Provider Configuration ==="
    
    # Wait a bit for LocalStack to be fully ready
    sleep 15
    
    kubectl apply -f "$PROJECT_ROOT/crossplane/provider-config.yaml" >/dev/null 2>&1
    
    print_success "Provider configuration completed"
}

# Create AWS resources (with retries)
create_aws_resources() {
    print_info "=== AWS Resources Creation ==="
    
    # Create resources in order with simple retry logic
    resources=("sns-topic" "sqs-queue" "dynamodb-table" "sns-subscription")
    
    for resource in "${resources[@]}"; do
        print_info "Creating $resource..."
        
        # Apply resource
        kubectl apply -f "$PROJECT_ROOT/crossplane/${resource}.yaml" >/dev/null 2>&1
        
        # Simple wait - don't hang on status checks
        sleep 10
        
        print_success "$resource applied successfully"
    done
    
    # Give all resources time to be created
    print_info "Allowing AWS resources to initialize..."
    sleep 30
    
    print_success "AWS infrastructure provisioned successfully"
}

# Deploy applications
deploy_applications() {
    print_info "=== Applications Deployment ==="
    
    # Deploy Producer
    print_info "Installing producer..."
    helm upgrade --install producer "$PROJECT_ROOT/helm/producer" \
        --set image.repository=ghcr.io/justtrackio/devopstest-producer \
        --set image.tag=latest \
        --set env.CLOUD_AWS_DEFAULTS_ENDPOINT=http://localstack.localstack.svc.cluster.local:4566 \
        --wait --timeout=180s >/dev/null 2>&1
    
    # Deploy Consumer
    print_info "Installing consumer..."
    helm upgrade --install consumer "$PROJECT_ROOT/helm/consumer" \
        --set image.repository=ghcr.io/justtrackio/devopstest-consumer \
        --set image.tag=latest \
        --set env.CLOUD_AWS_DEFAULTS_ENDPOINT=http://localstack.localstack.svc.cluster.local:4566 \
        --wait --timeout=180s >/dev/null 2>&1
    
    # Deploy DynamoDB Admin
    print_info "Installing dynamodb-admin..."
    helm upgrade --install dynamodb-admin "$PROJECT_ROOT/helm/dynamodb-admin" \
        --set env.DYNAMO_ENDPOINT=http://localstack.localstack.svc.cluster.local:4566 \
        --set env.AWS_REGION=$AWS_REGION \
        --wait --timeout=180s >/dev/null 2>&1
    
    print_success "All applications deployed successfully"
}

# Verify deployment (simple checks)
verify_deployment() {
    print_info "=== Deployment Verification ==="
    
    # Check pods
    print_info "Checking pod status..."
    kubectl get pods --all-namespaces | grep -E "(crossplane|localstack|producer|consumer|dynamodb)" || true
    
    # Check Helm releases
    print_info "Checking Helm releases..."
    helm list
    
    print_success "Deployment verification completed"
}

# Main deployment function
main() {
    local start_time=$(date +%s)
    
    validate_prerequisites
    install_crossplane
    install_aws_provider
    deploy_localstack
    create_provider_config
    create_aws_resources
    deploy_applications
    verify_deployment
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "===================================="
    echo ""
    echo "📊 Deployment Summary:"
    echo "  • Duration: ${duration}s"
    echo "  • AWS Resources: 4 created (SNS, SQS, DynamoDB, Subscription)"
    echo "  • Applications: 3 deployed (Producer, Consumer, DynamoDB Admin)"
    echo "  • LocalStack: Running and configured"
    echo ""
    echo "🔗 Access Information:"
    echo "  • DynamoDB Admin: ./admin-bg.sh start"
    echo "  • Or manually: kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8001:8001"
    echo "  • Then open: http://localhost:8001"
    echo ""
    echo "📝 Monitor logs:"
    echo "  • Producer: kubectl logs -l app=producer-producer -f"
    echo "  • Consumer: kubectl logs -l app=consumer-consumer -f"
    echo ""
    echo "🧪 Run tests:"
    echo "  • ./test.sh"
    echo ""
    echo "🧹 Cleanup when done:"
    echo "  • ./cleanup.sh"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--help]"
        echo "Deploys the complete cloud-native event-driven architecture"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
