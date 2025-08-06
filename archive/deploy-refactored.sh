#!/bin/bash

# Refactored Cloud-Native Infrastructure Deployment Script
# Modular, maintainable, and reliable deployment using best practices

# Set strict error handling
set -euo pipefail

# Track deployment start time
readonly DEPLOYMENT_START_TIME=$(date +%s)

# Get script directory and project root
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source utilities and load configuration
source "$PROJECT_ROOT/lib/utils.sh"

# Load configuration
load_config "$PROJECT_ROOT/config/deployment-config.yaml"

# Deployment banner
echo "🚀 Deploying Cloud-Native Event-Driven Architecture (Refactored)"
echo "================================================================="
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Cleanup function for error handling
cleanup() {
    print_info "Performing cleanup on error..."
    
    # Clean up any test resources
    kubectl delete pod localstack-test --ignore-not-found=true >/dev/null 2>&1 || true
    kubectl delete pod aws-test --ignore-not-found=true >/dev/null 2>&1 || true
    
    # Note: We don't clean up main resources on error to allow debugging
    print_info "Cleanup completed"
}

# Trap for cleanup on exit
trap cleanup EXIT

# Create AWS resources using Crossplane
create_aws_resources() {
    print_info "=== Creating AWS Resources ==="
    
    local resources_dir="$PROJECT_ROOT/crossplane"
    local resource_files=(
        "sns-topic.yaml"
        "sqs-queue.yaml"
        "dynamodb-table.yaml"
        "sns-subscription.yaml"
    )
    
    # Apply all resource files
    for resource_file in "${resource_files[@]}"; do
        local file_path="$resources_dir/$resource_file"
        
        if [ ! -f "$file_path" ]; then
            handle_error 1 "Resource file not found: $file_path"
        fi
        
        print_info "Applying $resource_file..."
        if kubectl apply -f "$file_path" >/dev/null 2>&1; then
            print_success "$resource_file applied"
        else
            handle_error $? "Failed to apply $resource_file"
        fi
    done
    
    # Wait for all resources to be ready
    print_info "Waiting for AWS resources to be ready..."
    
    local resources=(
        "topic:${AWS_RESOURCES[topic_name]}"
        "queue:${AWS_RESOURCES[queue_name]}"
        "table:${AWS_RESOURCES[table_name]}"
        "subscription:${AWS_RESOURCES[subscription_name]}"
    )
    
    for resource in "${resources[@]}"; do
        local resource_type="${resource%%:*}"
        local resource_name="${resource##*:}"
        
        if wait_for_resource "$resource_type" "$resource_name" "${TIMEOUTS[resource_wait]}"; then
            print_success "$resource_type '$resource_name' is ready"
        else
            handle_error 1 "Failed to create $resource_type '$resource_name'"
        fi
    done
    
    print_success "All AWS resources created successfully"
}

# Deploy applications using Helm
deploy_applications() {
    print_info "=== Deploying Applications ==="
    
    local apps=("producer" "consumer" "dynamodb-admin")
    
    for app in "${apps[@]}"; do
        print_info "Deploying $app..."
        
        local helm_dir="$PROJECT_ROOT/helm/$app"
        
        if [ ! -d "$helm_dir" ]; then
            handle_error 1 "Helm chart directory not found: $helm_dir"
        fi
        
        # Check if already installed
        if helm list | grep -q "^$app"; then
            print_info "$app already installed, upgrading..."
            if helm upgrade "$app" "$helm_dir" \
                --wait --timeout="${TIMEOUTS[helm_install]}s" >/dev/null 2>&1; then
                print_success "$app upgraded successfully"
            else
                handle_error $? "Failed to upgrade $app"
            fi
        else
            if helm install "$app" "$helm_dir" \
                --wait --timeout="${TIMEOUTS[helm_install]}s" >/dev/null 2>&1; then
                print_success "$app installed successfully"
            else
                handle_error $? "Failed to install $app"
            fi
        fi
        
        # Wait for deployment to be ready
        if kubectl rollout status deployment/"$app-$app" \
            --timeout="${TIMEOUTS[rollout_status]}s" >/dev/null 2>&1; then
            print_success "$app deployment is ready"
        else
            print_warning "$app deployment may still be starting"
        fi
    done
    
    print_success "All applications deployed successfully"
}

# Verify deployment
verify_deployment() {
    print_info "=== Verifying Deployment ==="
    
    # Wait for final stabilization
    print_info "Waiting for system stabilization..."
    sleep 15
    
    # Check Crossplane resources
    print_info "Checking Crossplane resources..."
    local ready_resources
    ready_resources=$(kubectl get topics,queues,tables,subscriptions \
        -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' \
        | grep -o True | wc -l)
    
    if [ "$ready_resources" -eq "${VERIFICATION[expected_resources]}" ]; then
        print_success "All Crossplane resources are ready (${ready_resources}/${VERIFICATION[expected_resources]})"
    else
        print_error "Not all Crossplane resources are ready (${ready_resources}/${VERIFICATION[expected_resources]})"
        return 1
    fi
    
    # Check application deployments
    print_info "Checking application deployments..."
    local ready_apps
    ready_apps=$(kubectl get deployments -l "app.kubernetes.io/managed-by=Helm" \
        --no-headers | grep -c "1/1" || echo "0")
    
    if [ "$ready_apps" -eq "${VERIFICATION[expected_applications]}" ]; then
        print_success "All applications are ready (${ready_apps}/${VERIFICATION[expected_applications]})"
    else
        print_error "Not all applications are ready (${ready_apps}/${VERIFICATION[expected_applications]})"
        return 1
    fi
    
    # Check LocalStack
    print_info "Checking LocalStack..."
    local localstack_ready
    localstack_ready=$(kubectl get deployment "${LOCALSTACK[service_name]}" \
        -n "${LOCALSTACK[namespace]}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    
    if [ "$localstack_ready" -gt 0 ]; then
        print_success "LocalStack is running"
    else
        print_error "LocalStack is not ready"
        return 1
    fi
    
    print_success "Deployment verification completed successfully"
    return 0
}

# Display deployment summary
show_deployment_summary() {
    local deployment_end_time
    deployment_end_time=$(date +%s)
    local deployment_duration
    deployment_duration=$((deployment_end_time - DEPLOYMENT_START_TIME))
    local duration_min
    duration_min=$((deployment_duration / 60))
    local duration_sec
    duration_sec=$((deployment_duration % 60))
    
    echo ""
    echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "====================================="
    echo ""
    echo "📊 Deployment Summary:"
    echo "  • Duration: ${duration_min}m ${duration_sec}s"
    echo "  • AWS Resources: ${VERIFICATION[expected_resources]} created"
    echo "  • Applications: ${VERIFICATION[expected_applications]} deployed"
    echo "  • LocalStack: Running"
    echo ""
    echo "🔗 Access Information:"
    echo "  • Producer: kubectl get pods -l app=producer"
    echo "  • Consumer: kubectl get pods -l app=consumer"
    echo "  • DynamoDB Admin: kubectl port-forward svc/dynamodb-admin-dynamodb-admin ${APPLICATIONS[dynamodb-admin][port]}:${APPLICATIONS[dynamodb-admin][port]}"
    echo ""
    echo "🧪 Testing:"
    echo "  • Check logs: kubectl logs -l app=producer"
    echo "  • Check logs: kubectl logs -l app=consumer"
    echo "  • Verify data: Access DynamoDB Admin interface"
    echo ""
    echo "✅ Event-driven architecture is ready!"
}

# Main deployment function
main() {
    print_info "Starting deployment with enhanced error handling and modular design"
    
    # Step 1: Validate prerequisites
    print_info "=== Prerequisites Validation ==="
    validate_prerequisites
    
    # Step 2: Setup certificates
    source "$PROJECT_ROOT/lib/setup-certificates.sh"
    main
    
    # Step 3: Install Crossplane
    source "$PROJECT_ROOT/lib/install-crossplane.sh"
    main
    
    # Step 4: Deploy LocalStack
    source "$PROJECT_ROOT/lib/deploy-localstack.sh"
    main
    
    # Step 5: Create AWS resources
    create_aws_resources
    
    # Step 6: Deploy applications
    deploy_applications
    
    # Step 7: Verify deployment
    verify_deployment
    
    # Step 8: Show summary
    show_deployment_summary
    
    print_success "🚀 Deployment pipeline completed successfully!"
}

# Run main function
main "$@"
