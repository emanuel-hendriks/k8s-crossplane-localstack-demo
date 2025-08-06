#!/bin/bash

# Crossplane Installation Module
# Handles Crossplane installation and provider setup

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Install Crossplane using Helm
install_crossplane() {
    print_info "Installing Crossplane..."
    
    # Check if already installed
    if helm list -n "${CROSSPLANE[namespace]}" | grep -q crossplane; then
        print_info "Crossplane already installed, upgrading..."
        
        if helm upgrade crossplane crossplane-stable/crossplane \
            --namespace "${CROSSPLANE[namespace]}" \
            --wait --timeout="${TIMEOUTS[helm_install]}s" >/dev/null 2>&1; then
            print_success "Crossplane upgraded successfully"
        else
            handle_error $? "Failed to upgrade Crossplane" \
                "Check Helm repository and network connectivity"
        fi
    else
        # Add Crossplane Helm repository
        if ! helm repo list | grep -q crossplane-stable; then
            print_info "Adding Crossplane Helm repository..."
            helm repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null 2>&1
            helm repo update >/dev/null 2>&1
        fi
        
        # Create namespace if it doesn't exist
        kubectl create namespace "${CROSSPLANE[namespace]}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
        
        # Install Crossplane
        if helm install crossplane crossplane-stable/crossplane \
            --namespace "${CROSSPLANE[namespace]}" \
            --wait --timeout="${TIMEOUTS[helm_install]}s" >/dev/null 2>&1; then
            print_success "Crossplane installed successfully"
        else
            handle_error $? "Failed to install Crossplane" \
                "Check Helm repository and network connectivity"
        fi
    fi
    
    # Wait for Crossplane to be ready
    if kubectl rollout status deployment/crossplane \
        -n "${CROSSPLANE[namespace]}" \
        --timeout="${TIMEOUTS[rollout_status]}s" >/dev/null 2>&1; then
        print_success "Crossplane is ready"
    else
        handle_error $? "Crossplane deployment failed to become ready" \
            "Check pod logs: kubectl logs -n ${CROSSPLANE[namespace]} deployment/crossplane"
    fi
}

# Install AWS Provider
install_aws_provider() {
    print_info "Installing AWS Provider..."
    
    # Apply provider configuration
    local provider_config="apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: ${CROSSPLANE[provider_name]}
spec:
  package: ${CROSSPLANE[provider_package]}
  runtimeConfigRef:
    apiVersion: pkg.crossplane.io/v1beta1
    kind: DeploymentRuntimeConfig
    name: ${CROSSPLANE[runtime_config]}"
    
    echo "$provider_config" | kubectl apply -f - >/dev/null 2>&1
    
    # Wait for provider to be ready
    if wait_for_provider "${CROSSPLANE[provider_name]}"; then
        print_success "AWS Provider installed and ready"
    else
        handle_error $? "AWS Provider installation failed" \
            "Check provider logs: kubectl logs -n ${CROSSPLANE[namespace]} -l pkg.crossplane.io/provider=${CROSSPLANE[provider_name]}"
    fi
}

# Create DeploymentRuntimeConfig
create_runtime_config() {
    print_info "Creating DeploymentRuntimeConfig..."
    
    local runtime_config_file="${PROJECT_ROOT}/crossplane/deployment-runtime-config.yaml"
    
    if [ ! -f "$runtime_config_file" ]; then
        handle_error 1 "DeploymentRuntimeConfig file not found" \
            "Expected file: $runtime_config_file"
    fi
    
    if kubectl apply -f "$runtime_config_file" >/dev/null 2>&1; then
        print_success "DeploymentRuntimeConfig created"
    else
        handle_error $? "Failed to create DeploymentRuntimeConfig" \
            "Check file syntax: $runtime_config_file"
    fi
}

# Create ProviderConfig
create_provider_config() {
    print_info "Creating ProviderConfig..."
    
    # Create AWS credentials secret
    local aws_secret="apiVersion: v1
kind: Secret
metadata:
  name: aws-creds
  namespace: ${CROSSPLANE[namespace]}
type: Opaque
data:
  credentials: $(echo -n "[default]
aws_access_key_id = test
aws_secret_access_key = test" | base64 -w 0)"
    
    echo "$aws_secret" | kubectl apply -f - >/dev/null 2>&1
    
    # Create ProviderConfig
    local provider_config="apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: ${CROSSPLANE[namespace]}
      name: aws-creds
      key: credentials
  endpoint:
    url: ${LOCALSTACK[endpoint]}
    hostnameImmutable: true"
    
    echo "$provider_config" | kubectl apply -f - >/dev/null 2>&1
    
    # Wait a moment for ProviderConfig to be processed
    sleep "${TIMEOUTS[sleep_interval]}"
    
    print_success "ProviderConfig created"
}

# Verify Crossplane installation
verify_crossplane() {
    print_info "Verifying Crossplane installation..."
    
    # Check Crossplane pods
    local crossplane_pods
    crossplane_pods=$(kubectl get pods -n "${CROSSPLANE[namespace]}" \
        --no-headers | grep Running | wc -l)
    
    if [ "$crossplane_pods" -ge 2 ]; then
        print_success "Crossplane pods are running ($crossplane_pods pods)"
    else
        print_error "Insufficient Crossplane pods running"
        return 1
    fi
    
    # Check provider status
    local provider_status
    provider_status=$(get_resource_status "providers" "${CROSSPLANE[provider_name]}" "Installed")
    
    if [ "$provider_status" = "True" ]; then
        print_success "AWS Provider is installed"
    else
        print_error "AWS Provider is not properly installed"
        return 1
    fi
    
    # Check ProviderConfig
    if resource_exists "providerconfig" "default"; then
        print_success "ProviderConfig is configured"
    else
        print_error "ProviderConfig not found"
        return 1
    fi
    
    return 0
}

# Main Crossplane setup function
main() {
    print_info "=== Crossplane Installation ==="
    
    install_crossplane
    create_runtime_config
    install_aws_provider
    create_provider_config
    verify_crossplane
    
    print_success "Crossplane installation completed"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
