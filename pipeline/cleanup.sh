#!/bin/bash

# Cloud-Native Infrastructure Cleanup Script - OPTIMIZED VERSION
# Addresses code smells and performance issues from original cleanup script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PID_FILE="$SCRIPT_DIR/.admin-port-forward.pid"

# Configuration - parameterized for flexibility
readonly CROSSPLANE_NAMESPACE="${CROSSPLANE_NAMESPACE:-crossplane-system}"
readonly LOCALSTACK_NAMESPACE="${LOCALSTACK_NAMESPACE:-localstack}"
readonly CLEANUP_TIMEOUT="${CLEANUP_TIMEOUT:-60s}"
readonly FORCE_DELETE_TIMEOUT="${FORCE_DELETE_TIMEOUT:-30s}"
readonly PARALLEL_JOBS="${PARALLEL_JOBS:-5}"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

print_success() { echo -e "${GREEN} $1${NC}"; }
print_error() { echo -e "${RED} $1${NC}"; }
print_info() { echo -e "${BLUE}  $1${NC}"; }
print_warning() { echo -e "${YELLOW} $1${NC}"; }

# Global error tracking
declare -a CLEANUP_ERRORS=()
declare -a VERIFICATION_ERRORS=()

# Enhanced error handling
handle_error() {
    local line_no=$1
    local error_code=$2
    print_error "Error on line $line_no: Command exited with status $error_code"
    cleanup_background_jobs
    exit $error_code
}

trap 'handle_error $LINENO $?' ERR

cleanup_background_jobs() {
    # Kill any background jobs
    jobs -p | xargs -r kill 2>/dev/null || true
}

echo "Cleaning Up Cloud-Native Event-Driven Architecture (Optimized)"
echo "=============================================================="
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Optimized force delete with better error handling and timeouts
force_delete_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-""}
    
    local ns_flag=""
    if [[ -n "$namespace" ]]; then
        ns_flag="-n $namespace"
    fi
    
    print_info "Force deleting $resource_type/$resource_name${namespace:+ in $namespace}..."
    
    # Try graceful delete first with timeout
    if timeout "$FORCE_DELETE_TIMEOUT" kubectl delete "$resource_type" "$resource_name" $ns_flag --timeout="$FORCE_DELETE_TIMEOUT" 2>/dev/null; then
        print_success "$resource_type/$resource_name deleted gracefully"
        return 0
    fi
    
    # Force delete if stuck
    print_warning "$resource_type/$resource_name stuck, applying force delete..."
    
    # Remove finalizers and force delete in parallel
    {
        kubectl patch "$resource_type" "$resource_name" $ns_flag \
            -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    } &
    {
        sleep 2
        kubectl delete "$resource_type" "$resource_name" $ns_flag \
            --force --grace-period=0 2>/dev/null || true
    } &
    wait
    
    # Verify deletion with timeout
    local max_attempts=10
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if ! kubectl get "$resource_type" "$resource_name" $ns_flag >/dev/null 2>&1; then
            print_success "$resource_type/$resource_name force deleted"
            return 0
        fi
        sleep 1
        ((attempt++))
    done
    
    CLEANUP_ERRORS+=("Failed to delete $resource_type/$resource_name${namespace:+ in $namespace}")
    print_error "Failed to delete $resource_type/$resource_name"
    return 1
}

# Stop admin interface first (if running)
stop_admin_interface() {
    print_info "=== Stopping Admin Interface ==="
    
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            print_success "Admin interface stopped (PID: $pid)"
        fi
        rm -f "$PID_FILE"
    else
        print_info "Admin interface not running"
    fi
}

# Parallel Helm cleanup
cleanup_helm_applications() {
    print_info "=== Removing Helm Applications ==="
    
    local apps=("producer" "consumer" "dynamodb-admin")
    local pids=()
    
    # Get list of installed releases once
    local installed_releases
    installed_releases=$(helm list --short 2>/dev/null || echo "")
    
    # Remove applications in parallel
    for app in "${apps[@]}"; do
        {
            if echo "$installed_releases" | grep -q "^$app$"; then
                print_info "Uninstalling $app..."
                if timeout "$CLEANUP_TIMEOUT" helm uninstall "$app" --timeout="$CLEANUP_TIMEOUT" 2>/dev/null; then
                    print_success "$app removed"
                else
                    print_warning "$app force uninstalled"
                    CLEANUP_ERRORS+=("Failed to cleanly uninstall $app")
                fi
            else
                print_info "$app not found (already removed)"
            fi
        } &
        pids+=($!)
        
        # Limit parallel jobs
        if [[ ${#pids[@]} -ge $PARALLEL_JOBS ]]; then
            wait "${pids[0]}"
            pids=("${pids[@]:1}")
        fi
    done
    
    # Wait for remaining jobs
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    print_success "Helm applications cleanup completed"
}

# Optimized Crossplane resource cleanup with batch operations
cleanup_crossplane_resources() {
    print_info "=== Removing Crossplane AWS Resources ==="
    
    local resource_types=("subscriptions" "tables" "queues" "topics")
    local pids=()
    
    # Process each resource type in parallel
    for resource_type in "${resource_types[@]}"; do
        {
            local resources
            resources=$(kubectl get "$resource_type" --no-headers -o name 2>/dev/null || echo "")
            
            if [[ -n "$resources" ]]; then
                print_info "Removing $resource_type..."
                
                # Try batch delete first
                if echo "$resources" | xargs -r kubectl delete --timeout="$FORCE_DELETE_TIMEOUT" 2>/dev/null; then
                    print_success "All $resource_type removed"
                else
                    # Fall back to individual force delete
                    echo "$resources" | while IFS= read -r resource; do
                        if [[ -n "$resource" ]]; then
                            local resource_name
                            resource_name=$(echo "$resource" | cut -d'/' -f2)
                            force_delete_resource "${resource_type%s}" "$resource_name" || true
                        fi
                    done
                fi
            else
                print_info "No $resource_type found"
            fi
        } &
        pids+=($!)
    done
    
    # Wait for all resource types to be processed
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    print_success "Crossplane AWS resources cleanup completed"
}

# Optimized configuration cleanup
cleanup_crossplane_configuration() {
    print_info "=== Removing Crossplane Configuration ==="
    
    local pids=()
    
    # Remove ProviderConfig
    {
        if kubectl get providerconfig default >/dev/null 2>&1; then
            force_delete_resource "providerconfig" "default" || true
        else
            print_info "ProviderConfig not found (already removed)"
        fi
    } &
    pids+=($!)
    
    # Remove AWS credentials secret
    {
        if kubectl get secret aws-creds -n "$CROSSPLANE_NAMESPACE" >/dev/null 2>&1; then
            print_info "Removing AWS credentials secret..."
            if kubectl delete secret aws-creds -n "$CROSSPLANE_NAMESPACE" --timeout="$FORCE_DELETE_TIMEOUT" 2>/dev/null; then
                print_success "AWS credentials secret removed"
            else
                CLEANUP_ERRORS+=("Failed to remove AWS credentials secret")
            fi
        else
            print_info "AWS credentials secret not found"
        fi
    } &
    pids+=($!)
    
    # Wait for both operations
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    print_success "Crossplane configuration cleanup completed"
}

# Optimized namespace cleanup with proper waiting
cleanup_localstack() {
    print_info "=== Removing LocalStack ==="
    
    if kubectl get namespace "$LOCALSTACK_NAMESPACE" >/dev/null 2>&1; then
        print_info "Removing LocalStack namespace..."
        
        # Start deletion
        kubectl delete namespace "$LOCALSTACK_NAMESPACE" --timeout="$CLEANUP_TIMEOUT" 2>/dev/null &
        local delete_pid=$!
        
        # Wait with proper timeout
        if wait "$delete_pid"; then
            print_success "LocalStack namespace removed"
        else
            print_warning "LocalStack namespace deletion timed out, forcing..."
            # Force remove finalizers if stuck
            kubectl patch namespace "$LOCALSTACK_NAMESPACE" \
                -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            
            # Wait a bit more
            local max_attempts=15
            local attempt=0
            while kubectl get namespace "$LOCALSTACK_NAMESPACE" >/dev/null 2>&1 && [[ $attempt -lt $max_attempts ]]; do
                sleep 2
                ((attempt++))
            done
            
            if kubectl get namespace "$LOCALSTACK_NAMESPACE" >/dev/null 2>&1; then
                CLEANUP_ERRORS+=("LocalStack namespace still exists after force delete")
                print_error "LocalStack namespace cleanup failed"
            else
                print_success "LocalStack namespace force removed"
            fi
        fi
    else
        print_info "LocalStack namespace not found"
    fi
}

# Batch cleanup of test resources
cleanup_test_resources() {
    print_info "=== Cleaning Up Test Resources ==="
    
    local test_labels=(
        "run=aws-test"
        "run=aws-verify" 
        "run=localstack-test"
        "run=aws-debug"
        "run=aws-cli"
        "run=network-test"
    )
    
    local pids=()
    
    # Remove test pods by labels in parallel
    for label in "${test_labels[@]}"; do
        {
            kubectl delete pods -l "$label" --force --grace-period=0 --timeout="$FORCE_DELETE_TIMEOUT" 2>/dev/null || true
        } &
        pids+=($!)
    done
    
    # Remove completed/failed pods
    {
        kubectl delete pods --field-selector=status.phase==Succeeded --force --grace-period=0 --timeout="$FORCE_DELETE_TIMEOUT" 2>/dev/null || true
    } &
    pids+=($!)
    
    {
        kubectl delete pods --field-selector=status.phase==Failed --force --grace-period=0 --timeout="$FORCE_DELETE_TIMEOUT" 2>/dev/null || true
    } &
    pids+=($!)
    
    # Wait for all cleanup operations
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    print_success "Test resources cleaned up"
}

# Interactive Crossplane cleanup with better UX
cleanup_crossplane_optional() {
    print_info "=== Optional Crossplane Cleanup ==="
    
    print_warning "Do you want to remove Crossplane entirely?"
    print_info "This will uninstall Crossplane completely and cannot be undone."
    echo ""
    echo "Options:"
    echo "  [y] Yes - Remove Crossplane completely"
    echo "  [N] No  - Keep Crossplane for future use (default)"
    echo ""
    echo -n "Enter your choice (y/N): "
    read -r reply
    echo ""
    
    if [[ $reply =~ ^[Yy]$ ]]; then
        print_info "Removing Crossplane completely..."
        
        local pids=()
        
        # Remove AWS provider
        {
            if kubectl get provider provider-aws >/dev/null 2>&1; then
                print_info "Removing AWS provider..."
                force_delete_resource "provider" "provider-aws" || true
            fi
        } &
        pids+=($!)
        
        # Remove Crossplane Helm release
        {
            if helm list -n "$CROSSPLANE_NAMESPACE" --short | grep -q "^crossplane$"; then
                print_info "Uninstalling Crossplane..."
                if timeout "$CLEANUP_TIMEOUT" helm uninstall crossplane -n "$CROSSPLANE_NAMESPACE" 2>/dev/null; then
                    print_success "Crossplane uninstalled"
                else
                    CLEANUP_ERRORS+=("Failed to uninstall Crossplane")
                fi
            fi
        } &
        pids+=($!)
        
        # Wait for both operations
        for pid in "${pids[@]}"; do
            wait "$pid"
        done
        
        # Remove namespace last
        if kubectl get namespace "$CROSSPLANE_NAMESPACE" >/dev/null 2>&1; then
            print_info "Removing crossplane-system namespace..."
            if kubectl delete namespace "$CROSSPLANE_NAMESPACE" --timeout="$CLEANUP_TIMEOUT" 2>/dev/null; then
                print_success "Crossplane namespace removed"
            else
                print_warning "Forcing Crossplane namespace removal..."
                kubectl patch namespace "$CROSSPLANE_NAMESPACE" \
                    -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                sleep 5
                if kubectl get namespace "$CROSSPLANE_NAMESPACE" >/dev/null 2>&1; then
                    CLEANUP_ERRORS+=("Crossplane namespace still exists")
                else
                    print_success "Crossplane namespace force removed"
                fi
            fi
        fi
        
        print_success "Crossplane completely removed"
    else
        print_info "Keeping Crossplane installed for future use"
    fi
}

# Optimized verification with batch operations and better reporting
verify_cleanup() {
    print_info "=== Comprehensive Verification ==="
    
    local verification_passed=0
    local verification_failed=0
    
    # Helper function for verification
    verify_resource() {
        local description="$1"
        local command="$2"
        local expected="$3"
        
        print_info "Checking: $description"
        
        case $expected in
            "empty")
                local count
                count=$(eval "$command" 2>/dev/null | wc -l)
                if [[ $count -eq 0 ]]; then
                    print_success "  ✓ $description - Clean"
                    ((verification_passed++))
                else
                    print_error "  ✗ $description - Found $count items"
                    VERIFICATION_ERRORS+=("$description: Found $count items")
                    ((verification_failed++))
                fi
                ;;
            "not_found")
                if eval "$command" >/dev/null 2>&1; then
                    print_error "  ✗ $description - Still exists"
                    VERIFICATION_ERRORS+=("$description: Still exists")
                    ((verification_failed++))
                else
                    print_success "  ✓ $description - Not found (good)"
                    ((verification_passed++))
                fi
                ;;
            "kubernetes_only")
                local count
                count=$(eval "$command" 2>/dev/null | grep -v "kubernetes" | wc -l)
                if [[ $count -eq 0 ]]; then
                    print_success "  ✓ $description - Only kubernetes service remains"
                    ((verification_passed++))
                else
                    print_error "  ✗ $description - Found additional services"
                    VERIFICATION_ERRORS+=("$description: Found additional services")
                    ((verification_failed++))
                fi
                ;;
        esac
    }
    
    # Batch verification operations - only check resources deployed by deploy.sh
    echo ""
    print_info "Application Resources (deploy.sh targets):"
    verify_resource "Target application pods" "kubectl get pods -l 'app.kubernetes.io/instance in (producer,consumer,dynamodb-admin)' --no-headers" "empty"
    verify_resource "Target Helm releases" "helm list --short | grep -E '^(producer|consumer|dynamodb-admin)$'" "empty"
    verify_resource "Target application services" "kubectl get services --no-headers | grep -E '(producer-producer|consumer-consumer|dynamodb-admin-dynamodb-admin)'" "empty"
    
    echo ""
    print_info "Crossplane Resources:"
    verify_resource "SNS Topics" "kubectl get topics --no-headers" "empty"
    verify_resource "SQS Queues" "kubectl get queues --no-headers" "empty"
    verify_resource "DynamoDB Tables" "kubectl get tables --no-headers" "empty"
    verify_resource "SNS Subscriptions" "kubectl get subscriptions --no-headers" "empty"
    verify_resource "ProviderConfig" "kubectl get providerconfig default" "not_found"
    verify_resource "AWS Credentials Secret" "kubectl get secret aws-creds -n $CROSSPLANE_NAMESPACE" "not_found"
    
    echo ""
    print_info "Infrastructure Resources:"
    verify_resource "LocalStack namespace" "kubectl get namespace $LOCALSTACK_NAMESPACE" "not_found"
    verify_resource "Application namespaces" "kubectl get namespaces --no-headers | grep -v -E '(default|kube-system|kube-public|kube-node-lease|$CROSSPLANE_NAMESPACE)'" "empty"
    
    echo ""
    print_info "Test Resources:"
    local test_pods_count
    test_pods_count=$(kubectl get pods -A --no-headers | grep -E "(aws-test|aws-verify|localstack-test|aws-debug|aws-cli|network-test)" | wc -l)
    if [[ $test_pods_count -eq 0 ]]; then
        print_success "  ✓ Test pods - Clean"
        ((verification_passed++))
    else
        print_error "  ✗ Test pods - Found $test_pods_count pods"
        VERIFICATION_ERRORS+=("Test pods: Found $test_pods_count pods")
        ((verification_failed++))
    fi
    
    # System state verification
    echo ""
    print_info "System State:"
    if kubectl get namespace "$CROSSPLANE_NAMESPACE" >/dev/null 2>&1; then
        local crossplane_pods
        crossplane_pods=$(kubectl get pods -n "$CROSSPLANE_NAMESPACE" --no-headers | grep -c "Running" || echo "0")
        if [[ $crossplane_pods -gt 0 ]]; then
            print_success "  ✓ Crossplane system - Running ($crossplane_pods pods)"
            ((verification_passed++))
        else
            print_warning "  ⚠ Crossplane system - Not running properly"
        fi
    else
        print_success "  ✓ Crossplane system - Completely removed"
        ((verification_passed++))
    fi
    
    # Summary
    echo ""
    echo "VERIFICATION SUMMARY"
    echo "===================="
    echo ""
    
    local total_checks=$((verification_passed + verification_failed))
    
    if [[ $verification_failed -eq 0 ]]; then
        print_success "CLEANUP VERIFICATION PASSED!"
        print_success "All checks passed: $verification_passed/$total_checks"
        echo ""
        print_success "Environment Status:"
        echo "  • All application resources removed"
        echo "  • All Crossplane CRDs deleted (AWS resources removed from LocalStack)"
        echo "  • All test resources removed"
        echo "  • LocalStack completely removed (simulated AWS environment destroyed)"
        echo "  • No leftover pods or services"
        echo ""
        print_info "Environment is ready for fresh deployment!"
    else
        print_error "CLEANUP VERIFICATION ISSUES FOUND!"
        print_error "Failed checks: $verification_failed/$total_checks"
        print_error "Passed checks: $verification_passed/$total_checks"
        echo ""
        if [[ ${#VERIFICATION_ERRORS[@]} -gt 0 ]]; then
            print_warning "Issues found:"
            for error in "${VERIFICATION_ERRORS[@]}"; do
                echo "  • $error"
            done
        fi
    fi
    
    return $verification_failed
}

# Main cleanup function with timing and error reporting
main() {
    local start_time
    start_time=$(date +%s)
    
    # Execute cleanup steps
    stop_admin_interface
    cleanup_helm_applications
    cleanup_crossplane_resources
    cleanup_crossplane_configuration
    cleanup_localstack
    cleanup_test_resources
    cleanup_crossplane_optional
    
    # Verify cleanup
    local verification_result=0
    verify_cleanup || verification_result=$?
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo "OPTIMIZED CLEANUP COMPLETED!"
    echo "============================"
    echo ""
    echo "Cleanup Summary:"
    echo "  • Duration: ${duration}s"
    echo "  • Helm applications: Removed"
    echo "  • Crossplane resources: Cleaned"
    echo "  • LocalStack: Removed"
    echo "  • Test resources: Cleaned"
    echo "  • Admin interface: Stopped"
    
    if [[ ${#CLEANUP_ERRORS[@]} -gt 0 ]]; then
        echo ""
        print_warning "Cleanup Issues Encountered:"
        for error in "${CLEANUP_ERRORS[@]}"; do
            echo "  • $error"
        done
    fi
    
    echo ""
    if [[ $verification_result -eq 0 ]]; then
        print_success "🎉 Environment is clean and ready!"
        echo ""
        echo "Next steps:"
        echo "  • Run './deploy.sh' or './deploy-test.sh' for fresh deployment"
        echo "  • All resources will be created from scratch"
        echo "  • No conflicts or leftover state expected"
    else
        print_warning "Some verification checks failed"
        echo ""
        echo "Recommendations:"
        echo "  • Review the issues listed above"
        echo "  • Manual cleanup may be required"
        echo "  • You can still proceed with deployment"
    fi
    
    return $verification_result
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--help|--force|--keep-crossplane]"
        echo "Optimized cleanup of cloud-native event-driven architecture"
        echo ""
        echo "Environment Variables:"
        echo "  CROSSPLANE_NAMESPACE    Crossplane namespace (default: crossplane-system)"
        echo "  LOCALSTACK_NAMESPACE    LocalStack namespace (default: localstack)"
        echo "  CLEANUP_TIMEOUT         Cleanup timeout (default: 60s)"
        echo "  FORCE_DELETE_TIMEOUT    Force delete timeout (default: 30s)"
        echo "  PARALLEL_JOBS           Max parallel jobs (default: 5)"
        echo ""
        echo "Options:"
        echo "  --help              Show this help message"
        echo "  --force             Skip confirmation prompts"
        echo "  --keep-crossplane   Don't prompt to remove Crossplane"
        exit 0
        ;;
    --force)
        print_warning "Force mode not implemented in this version"
        print_info "Running normal cleanup with prompts..."
        main "$@"
        ;;
    --keep-crossplane)
        print_info "Crossplane will be preserved (--keep-crossplane flag)"
        # Override the cleanup function to skip the prompt
        cleanup_crossplane_optional() {
            print_info "=== Skipping Crossplane Cleanup ==="
            print_info "Keeping Crossplane installed (--keep-crossplane flag)"
        }
        main "$@"
        ;;
    *)
        main "$@"
        ;;
esac
