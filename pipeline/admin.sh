#!/bin/bash

# DynamoDB Admin Interface Access Script
# Automatically starts port-forward and opens the admin interface

set -euo pipefail

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

echo "🌐 DynamoDB Admin Interface Launcher"
echo "===================================="
echo ""

# Check if DynamoDB Admin service exists
if ! kubectl get svc dynamodb-admin-dynamodb-admin >/dev/null 2>&1; then
    print_error "DynamoDB Admin service not found"
    print_info "Make sure the deployment is running: ./pipeline/deploy.sh"
    exit 1
fi

# Check if DynamoDB Admin pod is running
ADMIN_POD=$(kubectl get pods -l app.kubernetes.io/instance=dynamodb-admin -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$ADMIN_POD" ]; then
    print_error "DynamoDB Admin pod not found or not running"
    print_info "Check pod status: kubectl get pods | grep dynamodb-admin"
    exit 1
fi

print_success "DynamoDB Admin service found"
print_success "DynamoDB Admin pod is running: $ADMIN_POD"

# Check if port 8001 is already in use
if lsof -i :8001 >/dev/null 2>&1; then
    print_warning "Port 8001 is already in use"
    print_info "Checking if it's already our port-forward..."
    
    # Test if the existing connection works
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8001 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        print_success "DynamoDB Admin is already accessible at http://localhost:8001"
        print_info "Opening browser..."
        
        # Try to open browser (works on macOS)
        if command -v open >/dev/null 2>&1; then
            open http://localhost:8001
        else
            print_info "Please open your browser to: http://localhost:8001"
        fi
        
        print_info "Table to view: justtrack-dev-devops-consumer-events"
        exit 0
    else
        print_error "Port 8001 is occupied by another service"
        print_info "Please free port 8001 or use a different port"
        exit 1
    fi
fi

print_info "Starting port-forward to DynamoDB Admin interface..."

# Start port-forward in background
kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8001:8001 >/dev/null 2>&1 &
PORT_FORWARD_PID=$!

# Function to cleanup on exit
cleanup() {
    print_info "Stopping port-forward..."
    kill $PORT_FORWARD_PID 2>/dev/null || true
    wait $PORT_FORWARD_PID 2>/dev/null || true
    print_info "Port-forward stopped"
}

# Set trap to cleanup on script exit
trap cleanup EXIT INT TERM

# Wait for port-forward to establish
print_info "Waiting for connection to establish..."
sleep 3

# Test if the interface is accessible
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8001 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
    print_success "DynamoDB Admin interface is accessible!"
    print_info "URL: http://localhost:8001"
    print_info "Table: justtrack-dev-devops-consumer-events"
    
    # Try to open browser automatically (works on macOS)
    if command -v open >/dev/null 2>&1; then
        print_info "Opening browser..."
        open http://localhost:8001
    else
        print_info "Please open your browser to: http://localhost:8001"
    fi
    
    echo ""
    print_info "🎯 Instructions:"
    echo "  1. Browser should open automatically to http://localhost:8001"
    echo "  2. Look for table: justtrack-dev-devops-consumer-events"
    echo "  3. Click on the table to view stored events"
    echo "  4. You'll see events with Id, Number, and CreatedAt fields"
    echo ""
    print_warning "Keep this script running to maintain the connection"
    print_info "Press Ctrl+C to stop the admin interface"
    
    # Keep the script running
    echo ""
    print_info "Port-forward is active. Waiting..."
    wait $PORT_FORWARD_PID
    
else
    print_error "Failed to connect to DynamoDB Admin interface (HTTP $HTTP_CODE)"
    print_info "Check if the pod is ready: kubectl get pods | grep dynamodb-admin"
    exit 1
fi
