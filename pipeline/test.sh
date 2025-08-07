#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Cloud-Native Infrastructure Test Script
# Comprehensive testing with proper cleanup and timeout handling

echo "Testing Cloud-Native Event-Driven Architecture"
echo "================================================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_success() { echo -e "${GREEN}$1${NC}"; }
print_error() { echo -e "${RED}$1${NC}"; }
print_info() { echo -e "${BLUE}$1${NC}"; }
print_warning() { echo -e "${YELLOW}$1${NC}"; }
print_test() { echo -e "${CYAN}$1${NC}"; }

TESTS_PASSED=0
TESTS_FAILED=0

# Array to track background processes for cleanup
BACKGROUND_PIDS=()

# Cleanup function
cleanup() {
    print_info "Cleaning up background processes..."
    for pid in "${BACKGROUND_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            sleep 1
            kill -9 "$pid" 2>/dev/null
        fi
    done
    
    # Kill any remaining port-forwards
    pkill -f "kubectl port-forward" 2>/dev/null
    
    # Clean up any test pods
    kubectl delete pod --field-selector=status.phase=Succeeded -l run 2>/dev/null || true
}

# Set up signal handlers
trap cleanup EXIT INT TERM

test_result() {
    if [ $1 -eq 0 ]; then
        print_success "$2"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_error "$2"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Function to run commands with timeout (macOS compatible)
run_with_timeout() {
    local timeout_duration="$1"
    shift
    local command="$@"
    
    # Check if timeout command exists, otherwise use gtimeout or skip timeout
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_duration" bash -c "$command" 2>/dev/null
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$timeout_duration" bash -c "$command" 2>/dev/null
    else
        # Fallback: run without timeout on macOS
        bash -c "$command" 2>/dev/null
    fi
    return $?
}

# Function to validate system through application logs (with timeout)
validate_through_logs() {
    local component="$1"
    local expected_pattern="$2"
    local timeout_duration="${3:-10}"
    
    case $component in
        "producer")
            run_with_timeout "$timeout_duration" "kubectl logs -l app=producer-producer --tail=10 2>/dev/null | grep -q '$expected_pattern'"
            ;;
        "consumer") 
            run_with_timeout "$timeout_duration" "kubectl logs -l app=consumer-consumer --tail=10 2>/dev/null | grep -q '$expected_pattern'"
            ;;
        "localstack")
            run_with_timeout "$timeout_duration" "kubectl logs -n localstack -l app=localstack --tail=20 2>/dev/null | grep -q '$expected_pattern'"
            ;;
    esac
}

# Function to get pod status with timeout
get_pod_status() {
    local pod_name="$1"
    run_with_timeout 10 "kubectl get pod '$pod_name' -o jsonpath='{.status.phase}' 2>/dev/null"
}

# Function to get resource status with timeout
get_resource_status() {
    local resource_type="$1"
    local resource_name="$2"
    run_with_timeout 10 "kubectl get '$resource_type' '$resource_name' -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null"
}

echo ""
print_info "Test 1: Infrastructure Status"
echo "================================="

# Get pod information with timeout
PRODUCER_POD=$(run_with_timeout 10 "kubectl get pods --no-headers 2>/dev/null | grep producer-producer | awk '{print \$1}'" || echo "")
CONSUMER_POD=$(run_with_timeout 10 "kubectl get pods --no-headers 2>/dev/null | grep consumer-consumer | awk '{print \$1}'" || echo "")
ADMIN_POD=$(run_with_timeout 10 "kubectl get pods --no-headers 2>/dev/null | grep dynamodb-admin | awk '{print \$1}'" || echo "")

print_info "Discovered pods:"
echo "  • Producer: ${PRODUCER_POD:-"STOPPED (scaled to 0)"}"
echo "  • Consumer: ${CONSUMER_POD:-"NOT FOUND"}"
echo "  • DynamoDB Admin: ${ADMIN_POD:-"NOT FOUND"}"

# Test pod status with timeout
if [ -n "$PRODUCER_POD" ]; then
    PRODUCER_STATUS=$(get_pod_status "$PRODUCER_POD")
    test_result $([ "$PRODUCER_STATUS" = "Running" ] && echo 0 || echo 1) "Producer pod is running"
else
    print_warning "Producer is stopped (scaled to 0 replicas)"
fi

if [ -n "$CONSUMER_POD" ]; then
    CONSUMER_STATUS=$(get_pod_status "$CONSUMER_POD")
    test_result $([ "$CONSUMER_STATUS" = "Running" ] && echo 0 || echo 1) "Consumer pod is running"
else
    print_error "Consumer pod not found - application not deployed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [ -n "$ADMIN_POD" ]; then
    ADMIN_STATUS=$(get_pod_status "$ADMIN_POD")
    test_result $([ "$ADMIN_STATUS" = "Running" ] && echo 0 || echo 1) "DynamoDB Admin pod is running"
else
    print_error "DynamoDB Admin pod not found - application not deployed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
print_info "Test 2: Crossplane Resources"
echo "==============================="

# Check Crossplane resources with timeout
TOPIC_STATUS=$(get_resource_status "topic" "justtrack-dev-devops-producer-events")
test_result $([ "$TOPIC_STATUS" = "True" ] && echo 0 || echo 1) "SNS Topic is ready"

QUEUE_STATUS=$(get_resource_status "queue" "justtrack-dev-devops-consumer-events")
test_result $([ "$QUEUE_STATUS" = "True" ] && echo 0 || echo 1) "SQS Queue is ready"

TABLE_STATUS=$(get_resource_status "table" "justtrack-dev-devops-consumer-events")
test_result $([ "$TABLE_STATUS" = "True" ] && echo 0 || echo 1) "DynamoDB Table is ready"

SUBSCRIPTION_STATUS=$(get_resource_status "subscription" "justtrack-dev-devops-subscription")
test_result $([ "$SUBSCRIPTION_STATUS" = "True" ] && echo 0 || echo 1) "SNS-SQS Subscription is ready"

echo ""
print_info "Test 3: LocalStack Connectivity & Event Flow"
echo "============================================="

# Test LocalStack connectivity through logs (with timeout)
print_test "Validating LocalStack event processing through logs..."

# Check if LocalStack is processing SNS events
if validate_through_logs "localstack" "sns.Publish => 200" 15; then
    test_result 0 "SNS events are being published to LocalStack"
else
    test_result 1 "SNS events not detected in LocalStack logs"
fi

# Check if LocalStack is processing SQS events  
if validate_through_logs "localstack" "sqs.ReceiveMessage => 200" 15; then
    test_result 0 "SQS events are being consumed from LocalStack"
else
    test_result 1 "SQS events not detected in LocalStack logs"
fi

# Check if LocalStack is processing DynamoDB events
if validate_through_logs "localstack" "dynamodb.PutItem => 200" 15; then
    test_result 0 "DynamoDB events are being stored in LocalStack"
else
    test_result 1 "DynamoDB events not detected in LocalStack logs"
fi

# Validate complete event flow through application logs
print_test "Validating application event flow..."

if [ -n "$PRODUCER_POD" ] && validate_through_logs "producer" "published event" 10; then
    test_result 0 "Producer is successfully publishing events"
else
    test_result 1 "Producer event publishing not detected"
fi

if [ -n "$CONSUMER_POD" ] && validate_through_logs "consumer" "got event" 10; then
    test_result 0 "Consumer is successfully processing events"
else
    test_result 1 "Consumer event processing not detected"
fi

# Detailed Event Flow Verification (with timeout)
print_test "Verifying detailed event flow integrity..."

# Check producer logs with timeout
if [ -n "$PRODUCER_POD" ]; then
    PRODUCER_LOG=$(run_with_timeout 10 "kubectl logs '$PRODUCER_POD' --tail=5 2>/dev/null | grep 'published event with id' | head -1")
    if [ -n "$PRODUCER_LOG" ]; then
        PRODUCER_EVENT_ID=$(echo "$PRODUCER_LOG" | grep -o "published event with id [a-f0-9-]*" | cut -d' ' -f5)
        PRODUCER_EVENT_NO=$(echo "$PRODUCER_LOG" | grep -o "and no [0-9]*" | cut -d' ' -f3)
        test_result 0 "Producer writing to SNS (Event #$PRODUCER_EVENT_NO, ID: ${PRODUCER_EVENT_ID:0:8}...)"
    else
        test_result 1 "Producer not actively writing to SNS"
    fi
fi

# Check SNS-SQS subscription with timeout
SNS_SQS_LOG=$(run_with_timeout 10 "kubectl logs -n localstack -l app=localstack --tail=10 2>/dev/null | grep 'Topic.*publishing.*to subscribed' | head -1")
if [ -n "$SNS_SQS_LOG" ]; then
    test_result 0 "SNS-SQS subscription delivering messages"
else
    test_result 1 "SNS-SQS subscription not working"
fi

# Check consumer logs with timeout
if [ -n "$CONSUMER_POD" ]; then
    CONSUMER_LOG=$(run_with_timeout 10 "kubectl logs '$CONSUMER_POD' --tail=5 2>/dev/null | grep 'got event' | head -1")
    if [ -n "$CONSUMER_LOG" ]; then
        CONSUMER_EVENT_ID=$(echo "$CONSUMER_LOG" | grep -o "got event [a-f0-9-]*" | cut -d' ' -f3)
        CONSUMER_EVENT_NO=$(echo "$CONSUMER_LOG" | grep -o "with number [0-9]*" | cut -d' ' -f3)
        test_result 0 "Consumer receiving from SQS (Event #$CONSUMER_EVENT_NO, ID: ${CONSUMER_EVENT_ID:0:8}...)"
        
        # Verify event ID correlation between producer and consumer
        if [ -n "$PRODUCER_EVENT_NO" ] && [ -n "$CONSUMER_EVENT_NO" ]; then
            # Check if recent events are flowing (numbers should be close)
            if [ "$PRODUCER_EVENT_NO" -ge "$((CONSUMER_EVENT_NO - 5))" ] && [ "$PRODUCER_EVENT_NO" -le "$((CONSUMER_EVENT_NO + 5))" ]; then
                test_result 0 "Event flow correlation verified (Producer-Consumer sync)"
            else
                test_result 1 "Event flow correlation issue (Producer: #$PRODUCER_EVENT_NO, Consumer: #$CONSUMER_EVENT_NO)"
            fi
        fi
    else
        test_result 1 "Consumer not receiving events from SQS"
    fi
fi

# Check DynamoDB writes with timeout
DYNAMODB_LOG=$(run_with_timeout 10 "kubectl logs -n localstack -l app=localstack --tail=10 2>/dev/null | grep 'dynamodb.PutItem => 200' | wc -l | tr -d ' '")
if [ "$DYNAMODB_LOG" -gt 0 ] 2>/dev/null; then
    test_result 0 "DynamoDB receiving processed events ($DYNAMODB_LOG recent writes)"
else
    test_result 1 "DynamoDB not receiving processed events"
fi

echo ""
print_info "Test 4: DynamoDB Data Verification"
echo "=================================="

# Use direct LocalStack pod access for DynamoDB data (with timeout)
print_test "Retrieving DynamoDB table data via LocalStack pod..."

# Get LocalStack pod name with timeout
LOCALSTACK_POD=$(run_with_timeout 10 "kubectl get pods -n localstack -l app=localstack -o jsonpath='{.items[0].metadata.name}' 2>/dev/null")

DYNAMO_DATA=""
ITEM_COUNT=0

if [ -n "$LOCALSTACK_POD" ]; then
    # Try to get data directly from LocalStack pod with timeout
    DYNAMO_DATA=$(run_with_timeout 30 "kubectl exec -n localstack '$LOCALSTACK_POD' -- sh -c '
        export AWS_ACCESS_KEY_ID=test
        export AWS_SECRET_ACCESS_KEY=test
        export AWS_DEFAULT_REGION=eu-central-1
        export AWS_ENDPOINT_URL=http://localhost:4566
        aws dynamodb scan --table-name justtrack-dev-devops-consumer-events --max-items 3 2>/dev/null
    '" 2>/dev/null)
fi

# Parse results
if [ -n "$DYNAMO_DATA" ] && echo "$DYNAMO_DATA" | grep -q '"Items"'; then
    ITEM_COUNT=$(echo "$DYNAMO_DATA" | grep -o '"Count": [0-9]*' | grep -o '[0-9]*')
    ITEM_COUNT=${ITEM_COUNT:-0}
    
    print_info "DynamoDB Table Status: ACTIVE"
    print_info "Total Items in Table: $ITEM_COUNT"
    
    test_result $([ "$ITEM_COUNT" -gt 0 ] 2>/dev/null && echo 0 || echo 1) "DynamoDB Table contains data ($ITEM_COUNT items)"
    
    # Validate data structure
    if echo "$DYNAMO_DATA" | grep -q '"Id"' && echo "$DYNAMO_DATA" | grep -q '"S"'; then
        test_result 0 "Items have Id field (String type)"
    else
        test_result 1 "Items missing Id field (String type)"
    fi
    
    if echo "$DYNAMO_DATA" | grep -q '"Number"' && echo "$DYNAMO_DATA" | grep -q '"N"'; then
        test_result 0 "Items have Number field (Number type)"
    else
        test_result 1 "Items missing Number field (Number type)"
    fi
    
    if echo "$DYNAMO_DATA" | grep -q '"CreatedAt"' && echo "$DYNAMO_DATA" | grep -q '"S"'; then
        test_result 0 "Items have CreatedAt field (String type)"
    else
        test_result 1 "Items missing CreatedAt field (String type)"
    fi
    
    # Display sample data (truncated to avoid terminal overflow)
    echo ""
    print_info "Sample DynamoDB Items (first 3):"
    echo "================================="
    if command -v jq >/dev/null 2>&1; then
        echo "$DYNAMO_DATA" | jq '.Items[:3]' 2>/dev/null || echo "$DYNAMO_DATA" | head -20
    else
        echo "$DYNAMO_DATA" | head -20
    fi
    echo "================================="
    
else
    # Fallback: validate through LocalStack logs that data is being stored
    print_warning "Direct DynamoDB access failed, validating through LocalStack logs..."
    
    if validate_through_logs "localstack" "dynamodb.PutItem => 200" 10; then
        test_result 0 "DynamoDB data storage confirmed via LocalStack logs"
        print_info "Events are being stored successfully (confirmed via logs)"
    else
        test_result 1 "No DynamoDB storage activity detected"
    fi
    
    # Estimate item count from logs
    RECENT_PUTS=$(run_with_timeout 10 "kubectl logs -n localstack -l app=localstack --tail=100 2>/dev/null | grep -c 'dynamodb.PutItem => 200'" || echo "0")
    print_info "Recent DynamoDB writes detected: $RECENT_PUTS"
fi

echo ""
print_info "Test 5: DynamoDB Admin Interface Verification"
echo "==============================================="

# Check DynamoDB Admin service with timeout
ADMIN_SERVICE_EXISTS=$(run_with_timeout 10 "kubectl get svc dynamodb-admin-dynamodb-admin 2>/dev/null | grep -q '8001/TCP' && echo 'yes' || echo 'no'")
test_result $([ "$ADMIN_SERVICE_EXISTS" = "yes" ] && echo 0 || echo 1) "DynamoDB Admin service exists on port 8001"

# Test admin interface accessibility (with proper cleanup)
if [ "$ADMIN_SERVICE_EXISTS" = "yes" ]; then
    print_test "Testing DynamoDB Admin web interface..."
    
    print_info "Starting port-forward to test admin interface..."
    
    # Start port-forward in background with timeout
    timeout 30 kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8001:8001 >/dev/null 2>&1 &
    PORT_FORWARD_PID=$!
    BACKGROUND_PIDS+=($PORT_FORWARD_PID)
    
    # Give port-forward time to establish
    sleep 8
    
    # Test HTTP response with timeout
    HTTP_STATUS=$(run_with_timeout 10 "curl -s -o /dev/null -w '%{http_code}' http://localhost:8001" || echo "000")
    
    if [ "$HTTP_STATUS" = "200" ]; then
        test_result 0 "DynamoDB Admin interface is accessible (HTTP 200)"
        
        print_info "DynamoDB Admin Interface Details:"
        echo "  • URL: http://localhost:8001"
        echo "  • Status: Accessible and responding"
        echo "  • Purpose: View and manage DynamoDB table data"
        echo "  • Table: justtrack-dev-devops-consumer-events"
        echo "  • Total Items: $ITEM_COUNT events"
        echo ""
        echo "How to access:"
        echo "  1. Run: kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8001:8001"
        echo "  2. Open: http://localhost:8001"
        echo "  3. Navigate to table: justtrack-dev-devops-consumer-events"
        echo "  4. View all stored events"
    else
        test_result 1 "DynamoDB Admin interface accessibility (HTTP $HTTP_STATUS)"
    fi
    
    # Clean up port-forward immediately
    if kill -0 "$PORT_FORWARD_PID" 2>/dev/null; then
        kill "$PORT_FORWARD_PID" 2>/dev/null
        sleep 1
        kill -9 "$PORT_FORWARD_PID" 2>/dev/null
    fi
    
    # Remove from background pids array
    BACKGROUND_PIDS=("${BACKGROUND_PIDS[@]/$PORT_FORWARD_PID}")
else
    test_result 1 "DynamoDB Admin service does not exist"
fi

echo ""
print_info "Test 6: Event Processing Status"
echo "================================="

if [ -n "$PRODUCER_POD" ]; then
    # Producer is running
    if run_with_timeout 10 "kubectl logs '$PRODUCER_POD' --tail=5 2>/dev/null | grep -q 'published event'"; then
        test_result 0 "Producer is publishing events"
    else
        test_result 1 "Producer is not publishing events"
    fi
    
    CURRENT_PRODUCER_EVENT=$(run_with_timeout 10 "kubectl logs '$PRODUCER_POD' --tail=1 2>/dev/null | grep -o 'no [0-9]*' | grep -o '[0-9]*'")
    print_info "Current Producer Event: #${CURRENT_PRODUCER_EVENT:-"N/A"}"
else
    print_warning "Producer is stopped - no new events being generated"
    print_info "To restart: kubectl scale deployment producer-producer --replicas=1"
fi

# Check consumer status
if [ -n "$CONSUMER_POD" ]; then
    if run_with_timeout 10 "kubectl logs '$CONSUMER_POD' --tail=5 2>/dev/null | grep -q 'got event\\|processed.*messages'"; then
        test_result 0 "Consumer is ready to process events"
    else
        test_result 1 "Consumer is not processing events"
    fi
    
    LAST_CONSUMER_LOG=$(run_with_timeout 10 "kubectl logs '$CONSUMER_POD' --tail=1 2>/dev/null")
    if echo "$LAST_CONSUMER_LOG" | grep -q "processed 0 messages"; then
        print_info "Consumer status: Waiting for new events (no backlog)"
    elif echo "$LAST_CONSUMER_LOG" | grep -q "got event"; then
        LAST_EVENT=$(echo "$LAST_CONSUMER_LOG" | grep -o 'number [0-9]*' | grep -o '[0-9]*')
        print_info "Last processed event: #${LAST_EVENT:-"N/A"}"
    else
        print_info "Consumer status: Active and processing"
    fi
fi

echo ""
print_info "Test 7: System Health Summary"
echo "==============================="

# Helm deployments with timeout
HELM_STATUS=$(run_with_timeout 15 "helm list 2>/dev/null | grep -E '(producer|consumer|dynamodb-admin)' | wc -l" || echo "0")
test_result $([ "$HELM_STATUS" -eq 3 ] 2>/dev/null && echo 0 || echo 1) "All Helm releases are deployed ($HELM_STATUS/3)"

# Crossplane resources
CROSSPLANE_READY=$(run_with_timeout 15 "kubectl get topics,queues,tables,subscriptions -o jsonpath='{.items[*].status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null | grep -o True | wc -l" || echo "0")
test_result $([ "$CROSSPLANE_READY" -eq 4 ] 2>/dev/null && echo 0 || echo 1) "All Crossplane resources are ready ($CROSSPLANE_READY/4)"

echo ""
echo "TEST RESULTS SUMMARY"
echo "======================"

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

if [ $TESTS_FAILED -eq 0 ]; then
    echo ""
    print_success "ALL TESTS PASSED! ($TESTS_PASSED/$TOTAL_TESTS)"
    echo ""
    print_info "✨ Event-Driven Architecture Status: FULLY OPERATIONAL ✨"
    echo ""
    echo "📈 System Summary:"
    echo "  • Total Events Stored: $ITEM_COUNT"
    echo "  • DynamoDB Table: ACTIVE with complete data"
    echo "  • Admin Interface: Accessible at http://localhost:8001"
    echo "  • Producer Status: ${PRODUCER_POD:+"RUNNING"}${PRODUCER_POD:-"STOPPED (controlled)"}"
    echo "  • Consumer Status: READY"
    echo ""
    echo "🔗 Complete Event Flow:"
    echo "  Producer → SNS Topic → SQS Queue → Consumer → DynamoDB"
    echo "     PASS         PASS          PASS         PASS         PASS"
    echo ""
    print_info "🛠️  Management Commands:"
    echo "  • Start Producer: kubectl scale deployment producer-producer --replicas=1"
    echo "  • Stop Producer: kubectl scale deployment producer-producer --replicas=0"
    echo "  • View DynamoDB: kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8001:8001"
    if [ -n "$CONSUMER_POD" ]; then
        echo "  • Monitor Consumer: kubectl logs $CONSUMER_POD -f"
    fi
    echo ""
    exit 0
else
    echo ""
    print_error "SOME TESTS FAILED: $TESTS_FAILED/$TOTAL_TESTS failed, $TESTS_PASSED/$TOTAL_TESTS passed"
    echo ""
    print_info "Troubleshooting:"
    echo "  • Check pods: kubectl get pods"
    echo "  • Check resources: kubectl get topics,queues,tables,subscriptions"
    if [ -n "$CONSUMER_POD" ]; then
        echo "  • Check logs: kubectl logs $CONSUMER_POD"
    fi
    echo ""
    exit 1
fi
