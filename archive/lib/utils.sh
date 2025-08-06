#!/bin/bash

# Utility Functions Library
# Reusable functions for deployment scripts

# Set strict error handling
set -euo pipefail

# Check bash version and enable associative arrays if supported
if [ "${BASH_VERSION%%.*}" -ge 4 ]; then
    declare -A CONFIG
    declare -A TIMEOUTS
    declare -A AWS_RESOURCES
    declare -A LOCALSTACK
    declare -A CROSSPLANE
    declare -A CERTIFICATES
    declare -A VERIFICATION
    BASH_ARRAYS_SUPPORTED=true
else
    BASH_ARRAYS_SUPPORTED=false
    print_warning "Bash version < 4.0 detected. Using simplified configuration."
fi

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly GRAY='\033[0;37m'
readonly NC='\033[0m'

# Load configuration from YAML file
load_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        echo "❌ Configuration file not found: $config_file"
        exit 1
    fi
    
    # Set default values (fallback for older bash versions)
    TIMEOUT_PROVIDER_READY=180
    TIMEOUT_RESOURCE_READY=300
    TIMEOUT_ROLLOUT_STATUS=120
    TIMEOUT_HELM_INSTALL=300
    TIMEOUT_LOCALSTACK_READY=300
    TIMEOUT_PROGRESS_INTERVAL=30
    TIMEOUT_SLEEP_INTERVAL=10
    TIMEOUT_RESOURCE_WAIT=120
    TIMEOUT_RETRY_ATTEMPTS=3
    
    AWS_REGION="eu-central-1"
    AWS_TOPIC_NAME="justtrack-dev-devops-producer-events"
    AWS_QUEUE_NAME="justtrack-dev-devops-consumer-events"
    AWS_TABLE_NAME="justtrack-dev-devops-consumer-events"
    AWS_SUBSCRIPTION_NAME="justtrack-dev-devops-subscription"
    
    LOCALSTACK_NAMESPACE="localstack"
    LOCALSTACK_SERVICE_NAME="localstack"
    LOCALSTACK_PORT=4566
    LOCALSTACK_ENDPOINT="http://localstack.localstack.svc.cluster.local:4566"
    
    CROSSPLANE_NAMESPACE="crossplane-system"
    CROSSPLANE_PROVIDER_NAME="provider-aws"
    CROSSPLANE_PROVIDER_PACKAGE="xpkg.upbound.io/crossplane-contrib/provider-aws:v0.47.0"
    CROSSPLANE_RUNTIME_CONFIG="localstack-config"
    
    CERT_CONFIG_MAP_NAME="ca-certificates"
    CERT_FILE_PATH="/etc/ssl/certs/combined-ca-bundle.crt"
    CERT_LOCAL_FILE="certificates/combined-ca-bundle.crt"
    
    VERIFICATION_EXPECTED_RESOURCES=4
    VERIFICATION_EXPECTED_APPLICATIONS=3
    
    if [ "$BASH_ARRAYS_SUPPORTED" = true ]; then
        # Parse YAML configuration for bash 4+
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            
            # Parse key-value pairs
            if [[ "$line" =~ ^[[:space:]]*([^:]+):[[:space:]]*(.+)$ ]]; then
                local key="${BASH_REMATCH[1]// /}"
                local value="${BASH_REMATCH[2]}"
                
                # Remove quotes from value
                value="${value//\"/}"
                
                # Store in appropriate associative array based on section
                case "$key" in
                    provider_ready|resource_ready|rollout_status|helm_install|localstack_ready|progress_interval|sleep_interval|resource_wait|retry_attempts)
                        TIMEOUTS["$key"]="$value"
                        ;;
                    region|topic_name|queue_name|table_name|subscription_name)
                        AWS_RESOURCES["$key"]="$value"
                        ;;
                    namespace|service_name|port|endpoint)
                        LOCALSTACK["$key"]="$value"
                        ;;
                    provider_name|provider_package|runtime_config)
                        CROSSPLANE["$key"]="$value"
                        ;;
                    config_map_name|cert_file_path|local_cert_file)
                        CERTIFICATES["$key"]="$value"
                        ;;
                    expected_resources|expected_applications)
                        VERIFICATION["$key"]="$value"
                        ;;
                esac
            fi
        done < "$config_file"
    fi
}

# Get configuration value with fallback
get_config() {
    local section="$1"
    local key="$2"
    
    if [ "$BASH_ARRAYS_SUPPORTED" = true ]; then
        case "$section" in
            "timeouts") echo "${TIMEOUTS[$key]:-}" ;;
            "aws_resources") echo "${AWS_RESOURCES[$key]:-}" ;;
            "localstack") echo "${LOCALSTACK[$key]:-}" ;;
            "crossplane") echo "${CROSSPLANE[$key]:-}" ;;
            "certificates") echo "${CERTIFICATES[$key]:-}" ;;
            "verification") echo "${VERIFICATION[$key]:-}" ;;
        esac
    else
        # Fallback for older bash versions
        case "${section}_${key}" in
            "timeouts_provider_ready") echo "$TIMEOUT_PROVIDER_READY" ;;
            "timeouts_resource_ready") echo "$TIMEOUT_RESOURCE_READY" ;;
            "timeouts_rollout_status") echo "$TIMEOUT_ROLLOUT_STATUS" ;;
            "timeouts_helm_install") echo "$TIMEOUT_HELM_INSTALL" ;;
            "timeouts_localstack_ready") echo "$TIMEOUT_LOCALSTACK_READY" ;;
            "timeouts_progress_interval") echo "$TIMEOUT_PROGRESS_INTERVAL" ;;
            "timeouts_sleep_interval") echo "$TIMEOUT_SLEEP_INTERVAL" ;;
            "timeouts_resource_wait") echo "$TIMEOUT_RESOURCE_WAIT" ;;
            "timeouts_retry_attempts") echo "$TIMEOUT_RETRY_ATTEMPTS" ;;
            "aws_resources_region") echo "$AWS_REGION" ;;
            "aws_resources_topic_name") echo "$AWS_TOPIC_NAME" ;;
            "aws_resources_queue_name") echo "$AWS_QUEUE_NAME" ;;
            "aws_resources_table_name") echo "$AWS_TABLE_NAME" ;;
            "aws_resources_subscription_name") echo "$AWS_SUBSCRIPTION_NAME" ;;
            "localstack_namespace") echo "$LOCALSTACK_NAMESPACE" ;;
            "localstack_service_name") echo "$LOCALSTACK_SERVICE_NAME" ;;
            "localstack_port") echo "$LOCALSTACK_PORT" ;;
            "localstack_endpoint") echo "$LOCALSTACK_ENDPOINT" ;;
            "crossplane_namespace") echo "$CROSSPLANE_NAMESPACE" ;;
            "crossplane_provider_name") echo "$CROSSPLANE_PROVIDER_NAME" ;;
            "crossplane_provider_package") echo "$CROSSPLANE_PROVIDER_PACKAGE" ;;
            "crossplane_runtime_config") echo "$CROSSPLANE_RUNTIME_CONFIG" ;;
            "certificates_config_map_name") echo "$CERT_CONFIG_MAP_NAME" ;;
            "certificates_cert_file_path") echo "$CERT_FILE_PATH" ;;
            "certificates_local_cert_file") echo "$CERT_LOCAL_FILE" ;;
            "verification_expected_resources") echo "$VERIFICATION_EXPECTED_RESOURCES" ;;
            "verification_expected_applications") echo "$VERIFICATION_EXPECTED_APPLICATIONS" ;;
        esac
    fi
}
timestamp() {
    echo -e "${GRAY}[$(date '+%Y-%m-%d %H:%M:%S')]${NC}"
}

# Logging functions
print_success() { echo -e "$(timestamp) ${GREEN}✅ $1${NC}"; }
print_error() { echo -e "$(timestamp) ${RED}❌ $1${NC}"; }
print_info() { echo -e "$(timestamp) ${BLUE}ℹ️  $1${NC}"; }
print_warning() { echo -e "$(timestamp) ${YELLOW}⚠️  $1${NC}"; }

# Enhanced error handling with cleanup
handle_error() {
    local exit_code=$1
    local error_message="$2"
    local suggestion="${3:-}"
    
    if [ $exit_code -ne 0 ]; then
        print_error "$error_message"
        if [ -n "$suggestion" ]; then
            print_info "💡 Suggestion: $suggestion"
        fi
        
        # Call cleanup function if it exists
        if declare -f cleanup > /dev/null; then
            print_info "Running cleanup..."
            cleanup
        fi
        
        print_error "Deployment failed. Check the logs above for details."
        exit $exit_code
    fi
}

# Get Kubernetes resource status
get_resource_status() {
    local resource_type="$1"
    local resource_name="$2"
    local condition_type="$3"
    local namespace="${4:-}"
    
    local ns_flag=""
    if [ -n "$namespace" ]; then
        ns_flag="-n $namespace"
    fi
    
    kubectl get "$resource_type" "$resource_name" $ns_flag \
        -o jsonpath="{.status.conditions[?(@.type==\"$condition_type\")].status}" 2>/dev/null || echo ""
}

# Get resource condition message
get_resource_message() {
    local resource_type="$1"
    local resource_name="$2"
    local condition_type="$3"
    local namespace="${4:-}"
    
    local ns_flag=""
    if [ -n "$namespace" ]; then
        ns_flag="-n $namespace"
    fi
    
    kubectl get "$resource_type" "$resource_name" $ns_flag \
        -o jsonpath="{.status.conditions[?(@.type==\"$condition_type\")].message}" 2>/dev/null || echo ""
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-}"
    
    local ns_flag=""
    if [ -n "$namespace" ]; then
        ns_flag="-n $namespace"
    fi
    
    kubectl get "$resource_type" "$resource_name" $ns_flag >/dev/null 2>&1
}

# Wait for resource with enhanced retry logic
wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local timeout="${3:-$(get_config timeouts resource_ready)}"
    local retry_attempts="${4:-$(get_config timeouts retry_attempts)}"
    local namespace="${5:-}"
    
    print_info "Waiting for $resource_type '$resource_name' to be ready..."
    
    local count=0
    local attempt=1
    local last_status=""
    local progress_interval
    progress_interval=$(get_config timeouts progress_interval)
    local sleep_interval
    sleep_interval=$(get_config timeouts sleep_interval)
    
    while [ $count -lt "$timeout" ] && [ $attempt -le "$retry_attempts" ]; do
        # Check if resource exists
        if ! resource_exists "$resource_type" "$resource_name" "$namespace"; then
            print_warning "$resource_type '$resource_name' not found (attempt $attempt/$retry_attempts)"
            sleep "$sleep_interval"
            count=$((count + sleep_interval))
            continue
        fi
        
        local ready_status
        ready_status=$(get_resource_status "$resource_type" "$resource_name" "Ready" "$namespace")
        local sync_status
        sync_status=$(get_resource_status "$resource_type" "$resource_name" "Synced" "$namespace")
        
        if [ "$ready_status" = "True" ]; then
            print_success "$resource_type '$resource_name' is ready"
            return 0
        fi
        
        # Show progress and error details
        if [ "$sync_status" = "False" ]; then
            local error_msg
            error_msg=$(get_resource_message "$resource_type" "$resource_name" "Synced" "$namespace")
            if [ -n "$error_msg" ] && [ "$error_msg" != "$last_status" ]; then
                print_warning "$resource_type '$resource_name' sync error: $error_msg"
                last_status="$error_msg"
            fi
        fi
        
        # Show progress every interval
        if [ $((count % progress_interval)) -eq 0 ] && [ $count -gt 0 ]; then
            print_info "Still waiting for $resource_type '$resource_name'... (${count}s/${timeout}s, attempt $attempt/$retry_attempts)"
            print_info "Status: Ready=$ready_status, Synced=$sync_status"
        fi
        
        sleep "$sleep_interval"
        count=$((count + sleep_interval))
        
        # If timeout reached, try next attempt
        if [ $count -ge "$timeout" ] && [ $attempt -lt "$retry_attempts" ]; then
            print_warning "Timeout reached for attempt $attempt, retrying..."
            count=0
            attempt=$((attempt + 1))
            sleep "$sleep_interval"
        fi
    done
    
    print_error "Timeout waiting for $resource_type '$resource_name' after $retry_attempts attempts"
    
    # Show detailed status for debugging
    if resource_exists "$resource_type" "$resource_name" "$namespace"; then
        print_info "Resource status details:"
        local ns_flag=""
        if [ -n "$namespace" ]; then
            ns_flag="-n $namespace"
        fi
        kubectl describe "$resource_type" "$resource_name" $ns_flag || true
    fi
    
    return 1
}

# Wait for provider to be ready
wait_for_provider() {
    local provider_name="$1"
    local timeout="${2:-$(get_config timeouts provider_ready)}"
    
    print_info "Waiting for provider '$provider_name' to be ready..."
    
    local count=0
    local progress_interval
    progress_interval=$(get_config timeouts progress_interval)
    local sleep_interval
    sleep_interval=$(get_config timeouts sleep_interval)
    local crossplane_namespace
    crossplane_namespace=$(get_config crossplane namespace)
    
    while [ $count -lt "$timeout" ]; do
        local installed_status
        installed_status=$(get_resource_status "providers" "$provider_name" "Installed")
        local healthy_status
        healthy_status=$(get_resource_status "providers" "$provider_name" "Healthy")
        
        # Check for certificate errors
        local cert_error
        cert_error=$(get_resource_message "providers" "$provider_name" "Installed" | grep -i "certificate\|tls\|x509" || echo "")
        
        if [ -n "$cert_error" ] && [ $count -gt "$progress_interval" ]; then
            print_warning "Certificate error detected: $cert_error"
            print_info "This may be expected in corporate environments"
        fi
        
        # Check if provider pod is running
        local provider_pod_status
        provider_pod_status=$(kubectl get pods -n "$crossplane_namespace" \
            -l "pkg.crossplane.io/provider=$provider_name" \
            -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
        
        if [ "$installed_status" = "True" ] && [ "$healthy_status" = "True" ]; then
            print_success "Provider '$provider_name' is ready and healthy"
            return 0
        elif [ "$installed_status" = "True" ] && [ "$provider_pod_status" = "Running" ]; then
            # Provider installed and pod running, even if not marked healthy (common with corporate certificates)
            local health_error
            health_error=$(get_resource_message "providers" "$provider_name" "Healthy" | grep -i "certificate\|tls\|x509" || echo "")
            if [ -n "$health_error" ]; then
                print_warning "Provider installed but unhealthy due to certificate issue"
                print_info "Provider pod is running - continuing (common in corporate environments)"
                return 0
            fi
        fi
        
        # Show progress
        if [ $((count % progress_interval)) -eq 0 ] && [ $count -gt 0 ]; then
            print_info "Still waiting for provider... (${count}s/${timeout}s)"
            print_info "Status: Installed=$installed_status, Healthy=$healthy_status, Pod=$provider_pod_status"
        fi
        
        sleep "$sleep_interval"
        count=$((count + sleep_interval))
    done
    
    print_error "Timeout waiting for provider '$provider_name'"
    
    # Show detailed status
    print_info "Provider status details:"
    kubectl describe providers "$provider_name" || true
    
    # Check if at least installed
    local final_installed_status
    final_installed_status=$(get_resource_status "providers" "$provider_name" "Installed")
    if [ "$final_installed_status" = "True" ]; then
        print_warning "Provider is installed but may be unhealthy - continuing"
        print_info "This is common in corporate environments with certificate restrictions"
        return 0
    fi
    
    return 1
}

# Check if certificates are needed
check_certificates() {
    local cert_file="$1"
    
    if [ -f "$cert_file" ]; then
        print_info "Custom CA certificates found - configuring for corporate environment"
        return 0
    else
        print_info "No custom CA certificates found - using standard certificate handling"
        return 1
    fi
}

# Validate prerequisites
validate_prerequisites() {
    local missing_tools=()
    
    # Check required tools
    for tool in kubectl helm docker; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_info "Please install the missing tools and try again"
        return 1
    fi
    
    # Check Kubernetes connection
    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "Cannot connect to Kubernetes cluster"
        print_info "Please ensure kubectl is configured and cluster is accessible"
        return 1
    fi
    
    print_success "Prerequisites validated"
    return 0
}

# Cleanup function (to be called on error or exit)
cleanup() {
    print_info "Performing cleanup..."
    # This will be implemented by the main script
    # Each script can define its own cleanup function
}

# Export functions for use in other scripts
export -f load_config
export -f timestamp print_success print_error print_info print_warning
export -f handle_error
export -f get_resource_status get_resource_message resource_exists
export -f wait_for_resource wait_for_provider
export -f check_certificates validate_prerequisites
export -f cleanup
