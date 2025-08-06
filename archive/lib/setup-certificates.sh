#!/bin/bash

# Certificate Setup Module
# Handles corporate certificate configuration for Crossplane

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Setup certificates for corporate environments
setup_certificates() {
    local cert_file="${PROJECT_ROOT}/$(get_config certificates local_cert_file)"
    
    if ! check_certificates "$cert_file"; then
        print_info "No custom certificates needed"
        return 0
    fi
    
    print_info "Configuring CA certificates for corporate environment..."
    
    local config_map_name
    config_map_name=$(get_config certificates config_map_name)
    local crossplane_namespace
    crossplane_namespace=$(get_config crossplane namespace)
    
    # Delete existing ConfigMap if present
    kubectl delete configmap "$config_map_name" \
        -n "$crossplane_namespace" --ignore-not-found=true >/dev/null 2>&1
    
    # Create new ConfigMap with certificates
    if kubectl create configmap "$config_map_name" \
        --from-file="combined-ca-bundle.crt=$cert_file" \
        -n "$crossplane_namespace" >/dev/null 2>&1; then
        print_success "Certificate ConfigMap created successfully"
    else
        handle_error 1 "Failed to create certificate ConfigMap" \
            "Check if certificate file exists: $cert_file"
    fi
    
    return 0
}

# Update Crossplane deployment with certificates
update_crossplane_certificates() {
    local cert_file="${PROJECT_ROOT}/${CERTIFICATES[local_cert_file]}"
    
    if ! check_certificates "$cert_file"; then
        return 0
    fi
    
    print_info "Updating Crossplane deployment with certificate configuration..."
    
    # Check if Crossplane deployment exists
    if ! kubectl get deployment crossplane -n "${CROSSPLANE[namespace]}" >/dev/null 2>&1; then
        print_warning "Crossplane deployment not found - will be configured during installation"
        return 0
    fi
    
    # Patch Crossplane deployment to include certificate environment variable
    local patch_json='{
        "spec": {
            "template": {
                "spec": {
                    "containers": [{
                        "name": "crossplane",
                        "env": [{
                            "name": "SSL_CERT_FILE",
                            "value": "'"${CERTIFICATES[cert_file_path]}"'"
                        }],
                        "volumeMounts": [{
                            "name": "ca-certificates",
                            "mountPath": "/etc/ssl/certs",
                            "readOnly": true
                        }]
                    }],
                    "volumes": [{
                        "name": "ca-certificates",
                        "configMap": {
                            "name": "'"${CERTIFICATES[config_map_name]}"'"
                        }
                    }]
                }
            }
        }
    }'
    
    if kubectl patch deployment crossplane -n "${CROSSPLANE[namespace]}" \
        --type='merge' -p "$patch_json" >/dev/null 2>&1; then
        print_success "Crossplane deployment updated with certificates"
        
        # Wait for rollout to complete
        if kubectl rollout status deployment/crossplane \
            -n "${CROSSPLANE[namespace]}" \
            --timeout="${TIMEOUTS[rollout_status]}s" >/dev/null 2>&1; then
            print_success "Crossplane restarted with new certificate configuration"
        else
            print_warning "Crossplane rollout may still be in progress"
        fi
    else
        print_warning "Could not patch Crossplane deployment - may need manual configuration"
    fi
    
    return 0
}

# Verify certificate configuration
verify_certificates() {
    local cert_file="${PROJECT_ROOT}/${CERTIFICATES[local_cert_file]}"
    
    if ! check_certificates "$cert_file"; then
        print_success "Certificate verification skipped (no custom certificates)"
        return 0
    fi
    
    print_info "Verifying certificate configuration..."
    
    # Check if ConfigMap exists
    if kubectl get configmap "${CERTIFICATES[config_map_name]}" \
        -n "${CROSSPLANE[namespace]}" >/dev/null 2>&1; then
        print_success "Certificate ConfigMap exists"
    else
        print_error "Certificate ConfigMap not found"
        return 1
    fi
    
    # Check if Crossplane deployment has certificate configuration
    local ssl_cert_file
    ssl_cert_file=$(kubectl get deployment crossplane -n "${CROSSPLANE[namespace]}" \
        -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="SSL_CERT_FILE")].value}' 2>/dev/null || echo "")
    
    if [ "$ssl_cert_file" = "${CERTIFICATES[cert_file_path]}" ]; then
        print_success "Crossplane has correct certificate configuration"
    else
        print_warning "Crossplane certificate configuration may need updating"
    fi
    
    return 0
}

# Main certificate setup function
main() {
    print_info "=== Certificate Setup ==="
    
    setup_certificates
    update_crossplane_certificates
    verify_certificates
    
    print_success "Certificate setup completed"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
