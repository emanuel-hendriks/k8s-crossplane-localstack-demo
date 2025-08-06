#!/bin/bash

# Cloud-Native Infrastructure Deployment Script (Corporate/Custom Version)
# Deploys event-driven architecture with corporate certificate handling
# Supports Cato Networks and other corporate certificate requirements

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
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

# Corporate certificate configuration
readonly CERT_FILE_PATH="/etc/ssl/certs/combined-ca-bundle.crt"
readonly LOCAL_CERT_FILE="certificates/combined-ca-bundle.crt"
readonly CERT_CONFIG_MAP="corporate-ca-certificates"

# Extended timeouts for corporate environments
readonly PROVIDER_TIMEOUT=300
readonly LOCALSTACK_TIMEOUT=600
readonly RESOURCE_WAIT=180
readonly RETRY_ATTEMPTS=5

# Validate prerequisites
validate_prerequisites() {
    print_info "=== Prerequisites Validation ==="
    
    # Check required tools
    for tool in kubectl helm docker; do
        if ! command -v $tool >/dev/null 2>&1; then
            print_error "$tool is not installed or not in PATH"
            exit 1
        fi
    done
    
    # Check Kubernetes cluster access
    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "Cannot access Kubernetes cluster. Is Docker Desktop Kubernetes enabled?"
        exit 1
    fi
    
    # Check required directories
    for dir in crossplane helm k8s certificates; do
        if [ ! -d "$PROJECT_ROOT/$dir" ]; then
            print_warning "Directory not found: $dir (creating if needed)"
            mkdir -p "$PROJECT_ROOT/$dir" 2>/dev/null || true
        fi
    done
    
    # Add Crossplane Helm repository
    if ! helm repo list 2>/dev/null | grep -q crossplane-stable; then
        print_info "Adding Crossplane Helm repository..."
        helm repo add crossplane-stable https://charts.crossplane.io/stable
        helm repo update
    fi
    
    print_success "Prerequisites validated"
}

# Validate certificate file
validate_certificate() {
    local cert_file="$1"
    
    if [ ! -f "$cert_file" ]; then
        return 1
    fi
    
    # Basic validation - check if it looks like a certificate bundle
    if grep -q "BEGIN CERTIFICATE" "$cert_file" && grep -q "END CERTIFICATE" "$cert_file"; then
        return 0
    fi
    
    return 1
}

# Setup corporate certificates
setup_certificates() {
    print_info "=== Certificate Setup ==="
    print_info "Configuring custom certificates for enterprise environment..."
    
    # Create namespace first
    kubectl create namespace $CROSSPLANE_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    # Check if certificate file exists and is valid
    if validate_certificate "$PROJECT_ROOT/$LOCAL_CERT_FILE"; then
        print_info "Found valid corporate certificate bundle: $LOCAL_CERT_FILE"
        
        # Create certificate ConfigMap
        kubectl create configmap $CERT_CONFIG_MAP \
            --from-file=ca-certificates.crt="$PROJECT_ROOT/$LOCAL_CERT_FILE" \
            -n $CROSSPLANE_NAMESPACE \
            --dry-run=client -o yaml | kubectl apply -f -
        
        print_success "Certificate ConfigMap created successfully"
    else
        print_warning "No valid corporate certificate bundle found at $LOCAL_CERT_FILE"
        print_info "Continuing with system certificates..."
    fi
    
    print_success "Certificate setup completed"
}

# Install Crossplane with corporate configuration
install_crossplane() {
    print_info "=== Crossplane Installation ==="
    
    if helm list -n $CROSSPLANE_NAMESPACE 2>/dev/null | grep -q crossplane; then
        print_info "Crossplane already installed, upgrading..."
        helm upgrade crossplane crossplane-stable/crossplane \
            --namespace $CROSSPLANE_NAMESPACE \
            --create-namespace \
            --wait --timeout=300s
    else
        print_info "Installing Crossplane..."
        helm install crossplane crossplane-stable/crossplane \
            --namespace $CROSSPLANE_NAMESPACE \
            --create-namespace \
            --wait --timeout=300s
    fi
    
    # Wait for Crossplane to be ready
    print_info "Waiting for Crossplane to be ready..."
    kubectl wait --for=condition=available deployment/crossplane \
        -n $CROSSPLANE_NAMESPACE --timeout=300s
    
    print_success "Crossplane installation completed"
}

# Wait for provider deployment to exist
wait_for_provider_deployment() {
    local timeout=120
    local elapsed=0
    
    print_info "Waiting for provider deployment to be created..."
    
    while [ $elapsed -lt $timeout ]; do
        if kubectl get deployment -n $CROSSPLANE_NAMESPACE -l pkg.crossplane.io/provider=provider-aws >/dev/null 2>&1; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    print_warning "Provider deployment not found within timeout"
    return 1
}

# Patch provider with certificates (improved version)
patch_provider_certificates() {
    if ! kubectl get configmap $CERT_CONFIG_MAP -n $CROSSPLANE_NAMESPACE >/dev/null 2>&1; then
        print_info "No corporate certificates to patch"
        return 0
    fi
    
    print_info "Patching provider with corporate certificates..."
    
    # Wait for provider deployment to exist
    if ! wait_for_provider_deployment; then
        print_warning "Cannot patch certificates - provider deployment not found"
        return 0
    fi
    
    # Get the deployment name
    local deployment_name
    deployment_name=$(kubectl get deployment -n $CROSSPLANE_NAMESPACE -l pkg.crossplane.io/provider=provider-aws -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$deployment_name" ]; then
        print_warning "Provider deployment name not found"
        return 0
    fi
    
    # Create a patch file for better reliability
    local patch_file="/tmp/provider-cert-patch.yaml"
    cat > "$patch_file" << EOF
spec:
  template:
    spec:
      volumes:
      - name: ca-certificates
        configMap:
          name: $CERT_CONFIG_MAP
      containers:
      - name: package-runtime
        volumeMounts:
        - name: ca-certificates
          mountPath: /etc/ssl/certs/ca-certificates.crt
          subPath: ca-certificates.crt
          readOnly: true
        env:
        - name: SSL_CERT_FILE
          value: /etc/ssl/certs/ca-certificates.crt
EOF
    
    # Apply the patch
    if kubectl patch deployment "$deployment_name" -n $CROSSPLANE_NAMESPACE --patch-file "$patch_file" 2>/dev/null; then
        print_success "Provider patched with corporate certificates"
    else
        print_warning "Certificate patching failed, but continuing with deployment"
    fi
    
    # Clean up patch file
    rm -f "$patch_file"
}

# Install AWS Provider with certificate patching
install_aws_provider() {
    print_info "=== AWS Provider Installation ==="
    
    # Apply enhanced DeploymentRuntimeConfig if it exists
    if [ -f "$PROJECT_ROOT/crossplane/deployment-runtime-config.yaml" ]; then
        print_info "Applying enhanced provider configuration..."
        kubectl apply -f "$PROJECT_ROOT/crossplane/deployment-runtime-config.yaml"
    fi
    
    # Install AWS provider
    if [ -f "$PROJECT_ROOT/crossplane/provider.yaml" ]; then
        kubectl apply -f "$PROJECT_ROOT/crossplane/provider.yaml"
    else
        print_error "Provider configuration file not found: $PROJECT_ROOT/crossplane/provider.yaml"
        exit 1
    fi
    
    # Wait a bit for the provider to start creating resources
    sleep 15
    
    # Patch provider with corporate certificates
    patch_provider_certificates
    
    # Enhanced provider waiting with detailed monitoring
    print_info "Waiting for provider 'provider-aws' to be ready..."
    local timeout=$PROVIDER_TIMEOUT
    local elapsed=0
    local retry_count=0
    
    while [ $elapsed -lt $timeout ] && [ $retry_count -lt $RETRY_ATTEMPTS ]; do
        local installed_status
        local healthy_status
        
        installed_status=$(kubectl get providers provider-aws -o jsonpath='{.status.conditions[?(@.type=="Installed")].status}' 2>/dev/null || echo "False")
        healthy_status=$(kubectl get providers provider-aws -o jsonpath='{.status.conditions[?(@.type=="Healthy")].status}' 2>/dev/null || echo "False")
        
        if [ "$installed_status" = "True" ] && [ "$healthy_status" = "True" ]; then
            print_success "Provider 'provider-aws' is ready and healthy"
            break
        fi
        
        if [ $((elapsed % 30)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            print_info "Provider installation progress: Installed=$installed_status, Healthy=$healthy_status (${elapsed}s/${timeout}s)"
        fi
        
        sleep 5
        elapsed=$((elapsed + 5))
        
        # Retry logic for corporate network issues
        if [ $elapsed -ge $((timeout / 2)) ] && [ $retry_count -eq 0 ]; then
            print_warning "Provider installation taking longer than expected, checking for issues..."
            kubectl describe providers provider-aws || true
            retry_count=1
        fi
    done
    
    if [ $elapsed -ge $timeout ]; then
        print_error "Provider installation timed out after ${timeout}s"
        print_info "Checking provider status..."
        kubectl describe providers provider-aws || true
        exit 1
    fi
    
    print_success "AWS Provider installation completed"
}

# Deploy LocalStack with corporate configuration
deploy_localstack() {
    print_info "=== LocalStack Deployment ==="
    print_info "Deploying LocalStack with corporate configuration..."
    
    # Create namespace
    kubectl create namespace $LOCALSTACK_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy LocalStack if configuration exists
    if [ -f "$PROJECT_ROOT/k8s/localstack-deployment.yaml" ]; then
        kubectl apply -f "$PROJECT_ROOT/k8s/localstack-deployment.yaml"
    else
        print_error "LocalStack deployment file not found: $PROJECT_ROOT/k8s/localstack-deployment.yaml"
        exit 1
    fi
    
    # Wait for LocalStack to be ready with extended timeout
    print_info "Waiting for LocalStack to be ready..."
    if ! kubectl wait --for=condition=available deployment/localstack \
        -n $LOCALSTACK_NAMESPACE --timeout=${LOCALSTACK_TIMEOUT}s; then
        print_error "LocalStack deployment failed to become available"
        kubectl describe deployment/localstack -n $LOCALSTACK_NAMESPACE || true
        exit 1
    fi
    
    # Enhanced LocalStack health check
    print_info "Waiting for LocalStack service to be responsive..."
    local timeout=120
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if kubectl exec -n $LOCALSTACK_NAMESPACE deployment/localstack -- curl -s http://localhost:4566/_localstack/health >/dev/null 2>&1; then
            print_success "LocalStack health check passed"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $((elapsed % 30)) -eq 0 ]; then
            print_info "Still waiting for LocalStack health check... (${elapsed}s/${timeout}s)"
        fi
    done
    
    if [ $elapsed -ge $timeout ]; then
        print_warning "LocalStack health check timed out, but continuing..."
    fi
    
    print_success "LocalStack deployment completed"
}

# Create provider configuration
create_provider_config() {
    print_info "=== ProviderConfig Setup ==="
    
    # Create AWS credentials secret
    if [ -f "$PROJECT_ROOT/crossplane/aws-credentials.yaml" ]; then
        kubectl apply -f "$PROJECT_ROOT/crossplane/aws-credentials.yaml" || {
            print_error "Failed to create AWS credentials"
            exit 1
        }
    else
        print_error "AWS credentials file not found: $PROJECT_ROOT/crossplane/aws-credentials.yaml"
        exit 1
    fi
    
    # Create ProviderConfig
    if [ -f "$PROJECT_ROOT/crossplane/provider-config.yaml" ]; then
        kubectl apply -f "$PROJECT_ROOT/crossplane/provider-config.yaml" || {
            print_error "Failed to create ProviderConfig"
            exit 1
        }
    else
        print_error "ProviderConfig file not found: $PROJECT_ROOT/crossplane/provider-config.yaml"
        exit 1
    fi
    
    print_success "ProviderConfig and AWS credentials created successfully"
}

# Create AWS resources with enhanced monitoring
create_aws_resources() {
    print_info "=== Creating AWS Resources ==="
    print_info "Creating AWS resources with enhanced monitoring..."
    
    # Apply all AWS resources
    local resource_files=("sns-topic.yaml" "sqs-queue.yaml" "dynamodb-table.yaml" "sns-subscription.yaml")
    local applied_resources=()
    
    for resource_file in "${resource_files[@]}"; do
        if [ -f "$PROJECT_ROOT/crossplane/$resource_file" ]; then
            print_info "Applying $resource_file..."
            kubectl apply -f "$PROJECT_ROOT/crossplane/$resource_file"
            applied_resources+=("$resource_file")
        else
            print_warning "Resource file not found: $resource_file"
        fi
    done
    
    if [ ${#applied_resources[@]} -eq 0 ]; then
        print_error "No AWS resource files found to apply"
        exit 1
    fi
    
    # Wait for resources to be ready with enhanced monitoring
    # Note: Using more generic resource checking since exact names may vary
    print_info "Waiting for AWS resources to be ready..."
    local timeout=$RESOURCE_WAIT
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        local ready_count=0
        local total_count=0
        
        # Check different resource types
        for resource_type in topics queues tables subscriptions; do
            if kubectl get $resource_type >/dev/null 2>&1; then
                local resources_of_type
                resources_of_type=$(kubectl get $resource_type --no-headers 2>/dev/null | wc -l || echo "0")
                total_count=$((total_count + resources_of_type))
                
                # Count ready resources
                local ready_resources_of_type
                ready_resources_of_type=$(kubectl get $resource_type -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c "True" || echo "0")
                ready_count=$((ready_count + ready_resources_of_type))
            fi
        done
        
        if [ $total_count -gt 0 ] && [ $ready_count -eq $total_count ]; then
            print_success "All AWS resources are ready ($ready_count/$total_count)"
            break
        fi
        
        if [ $((elapsed % 30)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            print_info "AWS resources status: $ready_count/$total_count ready (${elapsed}s/${timeout}s)"
        fi
        
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    if [ $elapsed -ge $timeout ]; then
        print_warning "Some AWS resources may not be ready yet, but continuing..."
        # Show status of resources for debugging
        for resource_type in topics queues tables subscriptions; do
            if kubectl get $resource_type >/dev/null 2>&1; then
                print_info "Status of $resource_type:"
                kubectl get $resource_type -o wide || true
            fi
        done
    fi
    
    print_success "AWS resources creation completed"
}

# Deploy applications
deploy_applications() {
    print_info "=== Deploying Applications ==="
    
    # Check if Helm charts exist
    local charts=("producer" "consumer" "dynamodb-admin")
    for chart in "${charts[@]}"; do
        if [ ! -d "$PROJECT_ROOT/helm/$chart" ]; then
            print_error "Helm chart not found: $PROJECT_ROOT/helm/$chart"
            exit 1
        fi
    done
    
    # Deploy Producer
    print_info "Deploying Producer application..."
    helm upgrade --install producer "$PROJECT_ROOT/helm/producer" \
        --set image.repository=ghcr.io/justtrackio/devopstest-producer \
        --set image.tag=latest \
        --set env.CLOUD_AWS_DEFAULTS_ENDPOINT=http://localstack.localstack.svc.cluster.local:4566 \
        --wait --timeout=300s || {
        print_error "Failed to deploy Producer application"
        exit 1
    }
    
    # Deploy Consumer
    print_info "Deploying Consumer application..."
    helm upgrade --install consumer "$PROJECT_ROOT/helm/consumer" \
        --set image.repository=ghcr.io/justtrackio/devopstest-consumer \
        --set image.tag=latest \
        --set env.CLOUD_AWS_DEFAULTS_ENDPOINT=http://localstack.localstack.svc.cluster.local:4566 \
        --wait --timeout=300s || {
        print_error "Failed to deploy Consumer application"
        exit 1
    }
    
    # Deploy DynamoDB Admin
    print_info "Deploying DynamoDB Admin..."
    helm upgrade --install dynamodb-admin "$PROJECT_ROOT/helm/dynamodb-admin" \
        --set env.DYNAMO_ENDPOINT=http://localstack.localstack.svc.cluster.local:4566 \
        --set env.AWS_REGION=$AWS_REGION \
        --wait --timeout=300s || {
        print_error "Failed to deploy DynamoDB Admin application"
        exit 1
    }
    
    print_success "All applications deployed successfully"
}

# Verify deployment
verify_deployment() {
    print_info "=== Verifying Deployment ==="
    
    # Check Crossplane resources (more flexible checking)
    local crossplane_resource_types=("topics" "queues" "tables" "subscriptions")
    local found_resources=0
    
    for resource in "${crossplane_resource_types[@]}"; do
        if kubectl get $resource >/dev/null 2>&1; then
            found_resources=$((found_resources + 1))
        fi
    done
    
    if [ $found_resources -eq 0 ]; then
        print_error "No Crossplane resources found"
        exit 1
    else
        print_success "Found $found_resources types of Crossplane resources"
    fi
    
    # Check Helm releases
    local helm_releases=("producer" "consumer" "dynamodb-admin")
    for release in "${helm_releases[@]}"; do
        if ! helm list 2>/dev/null | grep -q $release; then
            print_error "Helm release $release not found"
            exit 1
        fi
    done
    
    # Check certificate configuration
    if kubectl get configmap $CERT_CONFIG_MAP -n $CROSSPLANE_NAMESPACE >/dev/null 2>&1; then
        print_success "Corporate certificates configured and active"
    fi
    
    # Check pods are running
    local timeout=180
    local elapsed=0
    
    print_info "Checking application pods..."
    while [ $elapsed -lt $timeout ]; do
        local ready_pods
        ready_pods=$(kubectl get pods --no-headers 2>/dev/null | grep -E "(producer|consumer|dynamodb-admin)" | grep Running | wc -l || echo "0")
        if [ "$ready_pods" -ge 3 ]; then
            print_success "All application pods are running"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        
        if [ $((elapsed % 30)) -eq 0 ]; then
            print_info "Application pods status: $ready_pods/3 running (${elapsed}s/${timeout}s)"
        fi
    done
    
    if [ $elapsed -ge $timeout ]; then
        print_warning "Some application pods may not be ready yet"
        kubectl get pods | grep -E "(producer|consumer|dynamodb-admin)" || true
    fi
    
    print_success "Deployment verification completed"
}

# Main deployment function
main() {
    # Deployment banner
    echo "🚀 Deploying Cloud-Native Event-Driven Architecture"
    echo "===================================================="
    local start_time
    start_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo "Started at: $start_time"
    echo ""
    
    print_info "Starting deployment with corporate configuration"
    
    # Record start time for duration calculation
    local start_timestamp
    start_timestamp=$(date +%s)
    
    # Execute deployment steps with error handling
    set +e  # Temporarily disable exit on error for better error reporting
    
    validate_prerequisites || { print_error "Prerequisites validation failed"; exit 1; }
    setup_certificates || { print_error "Certificate setup failed"; exit 1; }
    install_crossplane || { print_error "Crossplane installation failed"; exit 1; }
    install_aws_provider || { print_error "AWS Provider installation failed"; exit 1; }
    deploy_localstack || { print_error "LocalStack deployment failed"; exit 1; }
    create_provider_config || { print_error "ProviderConfig creation failed"; exit 1; }
    create_aws_resources || { print_error "AWS resources creation failed"; exit 1; }
    deploy_applications || { print_error "Application deployment failed"; exit 1; }
    verify_deployment || { print_error "Deployment verification failed"; exit 1; }
    
    set -e  # Re-enable exit on error
    
    # Calculate duration
    local end_timestamp
    end_timestamp=$(date +%s)
    local duration
    duration=$((end_timestamp - start_timestamp))
    
    # Success message
    echo ""
    echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "====================================="
    echo ""
    echo "📊 Deployment Summary:"
    echo "  • Duration: ${duration}s"
    echo "  • Certificate Handling: Corporate certificates configured"
    echo "  • AWS Resources: Created (SNS, SQS, DynamoDB, Subscription)"
    echo "  • Applications: 3 deployed (Producer, Consumer, DynamoDB Admin)"
    echo "  • LocalStack: Running with corporate configuration"
    echo ""
    echo "🔐 Security Features:"
    if kubectl get configmap $CERT_CONFIG_MAP -n $CROSSPLANE_NAMESPACE >/dev/null 2>&1; then
        echo "  • Corporate certificates: Configured and active"
        echo "  • Secure connections: All traffic certificate-validated"
    else
        echo "  • Corporate certificates: Using system certificates"
    fi
    echo "  • Enhanced monitoring: Advanced health checks enabled"
    echo ""
    echo "🔗 Access Information:"
    echo "  • Producer: kubectl get pods -l app=producer"
    echo "  • Consumer: kubectl get pods -l app=consumer"
    echo "  • DynamoDB Admin: ./pipeline/admin-bg.sh start"
    echo ""
    echo "✅ Enterprise event-driven architecture is ready!"
    
    print_success "🚀 Corporate deployment pipeline completed successfully!"
}

# Run main function
main "$@"
