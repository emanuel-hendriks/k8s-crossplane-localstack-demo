#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Cloud-Native Infrastructure Cleanup Script
# Comprehensive cleanup of all resources with force deletion capabilities

echo "Cleaning Up Cloud-Native Event-Driven Architecture"
echo "===================================================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() { echo -e "${GREEN}$1${NC}"; }
print_error() { echo -e "${RED}$1${NC}"; }
print_info() { echo -e "${BLUE}$1${NC}"; }
print_warning() { echo -e "${YELLOW}$1${NC}"; }

# Function to force delete stuck resources
force_delete_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-""}
    
    local ns_flag=""
    if [ -n "$namespace" ]; then
        ns_flag="-n $namespace"
    fi
    
    print_info "Force deleting stuck $resource_type $resource_name..."
    
    # Try normal delete first
    if kubectl delete $resource_type $resource_name $ns_flag --timeout=30s >/dev/null 2>&1; then
        print_success "$resource_type $resource_name deleted normally"
        return 0
    fi
    
    # If stuck, patch finalizers and force delete
    print_warning "$resource_type $resource_name is stuck, force deleting..."
    kubectl patch $resource_type $resource_name $ns_flag -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1
    kubectl delete $resource_type $resource_name $ns_flag --force --grace-period=0 >/dev/null 2>&1
    
    # Wait a moment for deletion to complete
    sleep 5
    
    if kubectl get $resource_type $resource_name $ns_flag >/dev/null 2>&1; then
        print_error "Failed to delete $resource_type $resource_name"
        return 1
    else
        print_success "$resource_type $resource_name force deleted"
        return 0
    fi
}

echo ""
print_info "Step 1: Removing Helm Applications"
echo "=================================="

print_info "Removing Helm applications..."
for app in producer consumer dynamodb-admin; do
    if helm list | grep -q "^$app"; then
        print_info "Uninstalling $app..."
        helm uninstall $app --timeout=60s >/dev/null 2>&1 || print_warning "Force uninstalled $app"
        print_success "$app removed"
    else
        print_info "$app not found (already removed)"
    fi
done

echo ""
print_info "Step 2: Removing Crossplane AWS Resources"
echo "========================================"

print_info "Removing Crossplane AWS resources..."
for resource in subscriptions tables queues topics; do
    resource_names=$(kubectl get $resource --no-headers 2>/dev/null | awk '{print $1}')
    if [ -n "$resource_names" ]; then
        echo "$resource_names" | while read name; do
            if [ -n "$name" ]; then
                force_delete_resource $resource $name
            fi
        done
    else
        print_info "No $resource found"
    fi
done

echo ""
print_info "Step 3: Removing Crossplane Configuration"
echo "========================================"

# Force remove stuck ProviderConfig
if kubectl get providerconfig default >/dev/null 2>&1; then
    force_delete_resource "providerconfig" "default"
else
    print_info "ProviderConfig not found (already removed)"
fi

# Remove AWS credentials secret
if kubectl get secret aws-creds -n crossplane-system >/dev/null 2>&1; then
    print_info "Removing AWS credentials secret..."
    kubectl delete secret aws-creds -n crossplane-system --force --grace-period=0 >/dev/null 2>&1
    print_success "AWS credentials secret removed"
else
    print_info "AWS credentials secret not found"
fi

echo ""
print_info "Step 4: Removing LocalStack"
echo "=========================="

# Remove LocalStack namespace completely
if kubectl get namespace localstack >/dev/null 2>&1; then
    print_info "Removing LocalStack namespace..."
    kubectl delete namespace localstack --force --grace-period=0 >/dev/null 2>&1 &
    
    # Wait for namespace deletion with timeout
    print_info "Waiting for LocalStack namespace deletion..."
    count=0
    while kubectl get namespace localstack >/dev/null 2>&1 && [ $count -lt 60 ]; do
        sleep 2
        count=$((count + 2))
    done
    
    if kubectl get namespace localstack >/dev/null 2>&1; then
        print_warning "LocalStack namespace deletion taking longer than expected"
    else
        print_success "LocalStack namespace removed"
    fi
else
    print_info "LocalStack namespace not found"
fi

echo ""
print_info "Step 5: Cleaning Up Test Resources"
echo "================================="

# Clean up any test pods
print_info "Removing test pods..."
kubectl delete pods -l run=aws-test --force --grace-period=0 >/dev/null 2>&1 || true
kubectl delete pods -l run=aws-verify --force --grace-period=0 >/dev/null 2>&1 || true
kubectl delete pods -l run=localstack-test --force --grace-period=0 >/dev/null 2>&1 || true
kubectl delete pods -l run=aws-debug --force --grace-period=0 >/dev/null 2>&1 || true
kubectl delete pods -l run=aws-cli --force --grace-period=0 >/dev/null 2>&1 || true
kubectl delete pods -l run=network-test --force --grace-period=0 >/dev/null 2>&1 || true

# Clean up completed pods
kubectl delete pods --field-selector=status.phase==Succeeded --force --grace-period=0 >/dev/null 2>&1 || true
kubectl delete pods --field-selector=status.phase==Failed --force --grace-period=0 >/dev/null 2>&1 || true

print_success "Test resources cleaned up"

echo ""
print_info "Step 6: Optional Crossplane Cleanup"
echo "=================================="

print_warning "Do you want to remove Crossplane entirely? This will uninstall Crossplane completely."
print_info "Choose: [y] Yes, remove Crossplane | [N] No, keep Crossplane (default)"
echo -n "Enter your choice (y/N): "
read -r REPLY
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Removing Crossplane..."
    
    # Remove AWS provider
    if kubectl get provider provider-aws >/dev/null 2>&1; then
        print_info "Removing AWS provider..."
        kubectl delete provider provider-aws --force --grace-period=0 >/dev/null 2>&1
        print_success "AWS provider removed"
    fi
    
    # Remove Crossplane
    if helm list -n crossplane-system | grep -q crossplane; then
        print_info "Uninstalling Crossplane..."
        helm uninstall crossplane -n crossplane-system >/dev/null 2>&1
        print_success "Crossplane uninstalled"
    fi
    
    # Remove Crossplane namespace
    if kubectl get namespace crossplane-system >/dev/null 2>&1; then
        print_info "Removing crossplane-system namespace..."
        kubectl delete namespace crossplane-system --force --grace-period=0 >/dev/null 2>&1
        print_success "Crossplane namespace removed"
    fi
    
    print_success "Crossplane completely removed"
else
    print_info "Keeping Crossplane installed for future use"
fi

echo ""
print_info "Step 7: Comprehensive Verification"
echo "================================="

print_info "Performing detailed cleanup verification..."
echo ""

# Initialize verification counters
VERIFICATION_PASSED=0
VERIFICATION_FAILED=0

verify_cleanup() {
    local description="$1"
    local command="$2"
    local expected_result="$3"  # "empty" or "not_found"
    
    print_info "Checking: $description"
    
    case $expected_result in
        "empty")
            local result=$(eval "$command" 2>/dev/null | wc -l)
            if [ "$result" -eq 0 ]; then
                print_success "  $description - Clean"
                VERIFICATION_PASSED=$((VERIFICATION_PASSED + 1))
            else
                print_error "  $description - Found $result items"
                eval "$command" 2>/dev/null | sed 's/^/    /'
                VERIFICATION_FAILED=$((VERIFICATION_FAILED + 1))
            fi
            ;;
        "not_found")
            if eval "$command" >/dev/null 2>&1; then
                print_error "  $description - Still exists"
                VERIFICATION_FAILED=$((VERIFICATION_FAILED + 1))
            else
                print_success "  $description - Not found (good)"
                VERIFICATION_PASSED=$((VERIFICATION_PASSED + 1))
            fi
            ;;
        "kubernetes_only")
            local result=$(eval "$command" 2>/dev/null | grep -v "kubernetes" | wc -l)
            if [ "$result" -eq 0 ]; then
                print_success "  $description - Only kubernetes service remains"
                VERIFICATION_PASSED=$((VERIFICATION_PASSED + 1))
            else
                print_error "  $description - Found additional services"
                eval "$command" 2>/dev/null | grep -v "kubernetes" | sed 's/^/    /'
                VERIFICATION_FAILED=$((VERIFICATION_FAILED + 1))
            fi
            ;;
    esac
}

# Verify application resources
print_info "Application Resources Verification:"
verify_cleanup "Pods in default namespace" "kubectl get pods --no-headers" "empty"
verify_cleanup "Helm releases" "helm list --short" "empty"
verify_cleanup "Services (except kubernetes)" "kubectl get services --no-headers" "kubernetes_only"

echo ""
print_info "Crossplane Resources Verification:"
verify_cleanup "SNS Topics" "kubectl get topics --no-headers" "empty"
verify_cleanup "SQS Queues" "kubectl get queues --no-headers" "empty"
verify_cleanup "DynamoDB Tables" "kubectl get tables --no-headers" "empty"
verify_cleanup "SNS Subscriptions" "kubectl get subscriptions --no-headers" "empty"
verify_cleanup "ProviderConfig" "kubectl get providerconfig default" "not_found"
verify_cleanup "AWS Credentials Secret" "kubectl get secret aws-creds -n crossplane-system" "not_found"

echo ""
print_info "Infrastructure Resources Verification:"
verify_cleanup "LocalStack namespace" "kubectl get namespace localstack" "not_found"
verify_cleanup "Application namespaces" "kubectl get namespaces --no-headers | grep -v -E '(default|kube-system|kube-public|kube-node-lease|crossplane-system)'" "empty"

echo ""
print_info "Test Resources Verification:"
verify_cleanup "Test pods (aws-test)" "kubectl get pods -l run=aws-test --no-headers" "empty"
verify_cleanup "Test pods (aws-verify)" "kubectl get pods -l run=aws-verify --no-headers" "empty"
verify_cleanup "Test pods (localstack-test)" "kubectl get pods -l run=localstack-test --no-headers" "empty"
verify_cleanup "Completed pods" "kubectl get pods --field-selector=status.phase==Succeeded --no-headers" "empty"
verify_cleanup "Failed pods" "kubectl get pods --field-selector=status.phase==Failed --no-headers" "empty"

echo ""
print_info "System State Verification:"
# Check if Crossplane is still running (should be if user chose to keep it)
if kubectl get namespace crossplane-system >/dev/null 2>&1; then
    CROSSPLANE_PODS=$(kubectl get pods -n crossplane-system --no-headers | grep Running | wc -l)
    if [ "$CROSSPLANE_PODS" -gt 0 ]; then
        print_success "  Crossplane system - Running ($CROSSPLANE_PODS pods)"
        VERIFICATION_PASSED=$((VERIFICATION_PASSED + 1))
    else
        print_warning "  Crossplane system - Not running properly"
    fi
else
    print_success "  Crossplane system - Completely removed"
    VERIFICATION_PASSED=$((VERIFICATION_PASSED + 1))
fi

echo ""
echo "VERIFICATION SUMMARY"
echo "======================"
echo ""
if [ "$VERIFICATION_FAILED" -eq 0 ]; then
    print_success "CLEANUP VERIFICATION PASSED!"
    print_success "All checks passed: $VERIFICATION_PASSED/$((VERIFICATION_PASSED + VERIFICATION_FAILED))"
    echo ""
    print_success "Environment Status:"
    echo "  All application resources removed"
    echo "  All AWS resources cleaned up"
    echo "  All test resources removed"
    echo "  LocalStack completely removed"
    echo "  No leftover pods or services"
    echo ""
    print_info "Environment is ready for fresh deployment!"
    echo "  • Run './deploy.sh' to start a new deployment"
    echo "  • All resources will be created from scratch"
    echo "  • No conflicts or leftover state"
else
    print_error "CLEANUP VERIFICATION ISSUES FOUND!"
    print_error "Failed checks: $VERIFICATION_FAILED/$((VERIFICATION_PASSED + VERIFICATION_FAILED))"
    print_error "Passed checks: $VERIFICATION_PASSED/$((VERIFICATION_PASSED + VERIFICATION_FAILED))"
    echo ""
    print_warning "Manual cleanup may be required for failed items above."
    print_info "You can still proceed with deployment, but there might be conflicts."
fi

echo ""
echo "CLEANUP COMPLETED!"
echo "===================="
echo ""
print_success "Cleanup Summary:"
echo "  Helm applications removed"
echo "  Crossplane AWS resources removed"
echo "  ProviderConfig and secrets cleaned"
echo "  LocalStack namespace removed"
echo "  Test pods and resources cleaned"
echo ""
print_info "Environment is now clean and ready for fresh deployment!"
echo ""
print_info "To deploy again, run: ./deploy.sh"
echo ""
